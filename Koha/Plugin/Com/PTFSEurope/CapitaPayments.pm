use utf8;

package Koha::Plugin::Com::PTFSEurope::CapitaPayments;

=head1 NAME

Koha::Plugin::Com::PTFSEurope::CapitaPayments

=cut

use Modern::Perl;

use base qw(Koha::Plugins::Base);

use C4::Context;
use C4::Circulation;
use C4::Auth;

use Koha::Account;
use Koha::Account::Lines;
use Koha::Patrons;

use Mojo::Util qw(b64_decode);
use Digest::SHA qw(hmac_sha256_base64);
use Time::Moment;
use File::Basename;
use Data::GUID;

use XML::Compile::WSDL11;
use XML::Compile::SOAP11;
use XML::Compile::Transport::SOAPHTTP;

## Here we set our plugin version
our $VERSION = "00.00.04";
our $debug   = 0;

## Here is our metadata, some keys are required, some are optional
our $metadata = {
    name            => 'Capita Online Payments Plugin',
    author          => 'Martin Renvoize',
    date_authored   => '2018-06-13',
    date_updated    => "2018-06-13",
    minimum_version => '17.11.00.000',
    maximum_version => '17.11.18.000',
    version         => $VERSION,
    description     => 'This plugin implements online payments using '
      . 'Capita Educations payments platform.',
};

our $root = dirname(__FILE__);
our $wsdl =
  XML::Compile::WSDL11->new( $root . '/CapitaPayments/scpSimpleClient.wsdl' );
$wsdl->importDefinitions( $root . '/CapitaPayments/scpSimple.xsd' );
$wsdl->importDefinitions( $root . '/CapitaPayments/scpBaseTypes.xsd' );
$wsdl->importDefinitions( $root . '/CapitaPayments/commonPaymentTypes.xsd' );
$wsdl->importDefinitions( $root . '/CapitaPayments/commonFoundationTypes.xsd' );

sub new {
    my ( $class, $args ) = @_;

    ## We need to add our metadata here so our base class can access it
    $args->{'metadata'} = $metadata;
    $args->{'metadata'}->{'class'} = $class;

    ## Here, we call the 'new' method for our base class
    ## This runs some additional magic and checking
    ## and returns our actual $self
    my $self = $class->SUPER::new($args);

    return $self;
}

sub opac_online_payment {
    my ( $self, $args ) = @_;

    return $self->retrieve_data('enable_opac_payments') eq 'Yes';
}

=head2 opac_online_payment_begin

  Initiate online payment process

=cut

sub opac_online_payment_begin {
    my ( $self, $args ) = @_;
    my $cgi    = $self->{'cgi'};
    my $schema = Koha::Database->new()->schema();

    my ( $borrowernumber, $cookie, $sessionID ) =
      checkauth( $cgi, 0, undef, 'opac' );

    # Generate unique transaction id
    my $transactionGUID = Data::GUID->new->as_string;

    # Get the borrower
    my $borrower = Koha::Patrons->find($borrowernumber);

    # Construct return URI
    my $return = C4::Context->preference('OPACBaseURL')
      . "/cgi-bin/koha/opac-account-pay-return.pl";
    my $returnURL = URI->new($return);
    $returnURL->query_form(
        {
            payment_method => scalar $cgi->param('payment_method'),
            txn            => $transactionGUID
        }
    );
    $returnURL = $returnURL->as_string;

    # Construct cancel URI
    my $cancelURL =
      C4::Context->preference('OPACBaseURL') . "/cgi-bin/koha/opac-account.pl";

    # Credentials
    my $Pay360SiteID   = $self->retrieve_data('Pay360SiteID');
    my $Pay360HMACID   = $self->retrieve_data('Pay360HMACID');
    my $Pay360PortalID = $self->retrieve_data('Pay360PortalID');
    my $requestGUID    = Data::GUID->new->as_string;
    my $timeStamp      = Time::Moment->now_utc->strftime('%Y%m%d%H%M%S');
    my $currentDigest  = $self->get_digest(
        'CapitaPortal', $Pay360PortalID, $requestGUID, $timeStamp,
        'Original',     $Pay360HMACID
    );

    # items
    my $sum_amountInMinorUnits = 0;
    my @accountline_ids        = $cgi->multi_param('accountline');
    my $accountlines           = $schema->resultset('Accountline')
      ->search( { accountlines_id => \@accountline_ids } );
    my $items;
    for my $accountline ( $accountlines->all ) {
        my $amount = sprintf "%.2f", $accountline->amountoutstanding;
        $amount                 = $amount * 100;
        $sum_amountInMinorUnits = $sum_amountInMinorUnits + $amount;

        my $item = {
            itemSummary => {
                description => ( $accountline->description )
                ? $accountline->description
                : "Description not available",
                amountInMinorUnits   => $amount,
                reference            => $accountline->accountlines_id,
                displayableReference => $accountline->accountlines_id,
            },
            quantity => 1,
            lineId   => $accountline->accountlines_id,
        };
        push @{$items}, $item;
    }

    my $request = {
        credentials => {
            subject => {
                subjectType => 'CapitaPortal',
                identifier  => $Pay360PortalID,
                systemCode  => 'SCP'
            },
            requestIdentification => {
                uniqueReference => $requestGUID,
                timeStamp       => $timeStamp
            },
            signature => {
                algorithm => 'Original',
                hmacKeyID => $Pay360HMACID,
                digest    => $currentDigest
            },
        },
        requestType => 'payOnly',
        requestId   => $transactionGUID,
        routing     => {
            returnUrl => $returnURL,
            backUrl   => $cancelURL,
            siteId    => $Pay360SiteID,
            scpId     => $Pay360PortalID,
        },
        panEntryMethod => 'ECOM',
        billing        => {
            cardHolderDetails => {
                cardHolderName => $borrower->firstname . " "
                  . $borrower->surname,
                contact => {
                    email => $borrower->email
                }
            }
        },
        sale => {
            saleSummary => {
                description        => 'Library Payment',
                amountInMinorUnits => $sum_amountInMinorUnits,
            },
            items => {
                item => $items
            }
        }
    };

    my $portal = $self->retrieve_data('Pay360Portal');
    my $scpSimpleInvoke =
      $wsdl->compileClient( operation => 'scpSimpleInvoke' );

    my $response = $scpSimpleInvoke->($request);

    # Handle errors
    if (
        exists(
            $response->{'scpSimpleInvokeResponse'}->{'invokeResult'}
              ->{'errorDetails'}
        )
      )
    {
        use Data::Dumper;
        warn Dumper( $response->{'scpSimpleInvokeResponse'}->{'invokeResult'}
              ->{'errorDetails'} );
        exit;    #FIXME: Return error page here
    }

    # Sucess
    else {

        # Store the transaction
        my $dbh   = C4::Context->dbh;
        my $table = $self->get_qualified_table_name('pay360_transactions');
        my $sth =
          $dbh->prepare(
"INSERT INTO $table (`transaction_guid`, `transaction_reference`, `transaction_state`) VALUES (?, ?, ?)"
          );
        $sth->execute(
            $transactionGUID,
            $response->{'scpSimpleInvokeResponse'}->{'scpReference'},
            $response->{'scpSimpleInvokeResponse'}->{'transactionState'}
        );

        print $cgi->redirect(
            $response->{'scpSimpleInvokeResponse'}->{'invokeResult'}
              ->{'redirectUrl'} );
        exit;
    }
}

=head2 opac_online_payment_end

  Complete online payment process

=cut

sub opac_online_payment_end {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    my ( $template, $borrowernumber ) = get_template_and_user(
        {
            template_name   => $self->mbf_path('opac_online_payment_end.tt'),
            query           => $cgi,
            type            => 'opac',
            authnotrequired => 0,
            is_plugin       => 1,
        }
    );

    my $transactionGUID = $cgi->param('txn');

    # Credentials
    my $Pay360SiteID   = $self->retrieve_data('Pay360SiteID');
    my $Pay360HMACID   = $self->retrieve_data('Pay360HMACID');
    my $Pay360PortalID = $self->retrieve_data('Pay360PortalID');
    my $requestGUID    = Data::GUID->new->as_string;
    my $timeStamp      = Time::Moment->now_utc->strftime('%Y%m%d%H%M%S');
    my $currentDigest  = $self->get_digest(
        'CapitaPortal', $Pay360PortalID, $transactionGUID, $timeStamp,
        'Original',     $Pay360HMACID
    );

    # Fetch scpReference
    my $table = $self->get_qualified_table_name('pay360_transactions');
    my $dbh   = C4::Context->dbh;
    my $sth   = $dbh->prepare(
        "SELECT transaction_reference FROM $table WHERE transaction_guid = ?");
    $sth->execute($transactionGUID);
    my ($scpReference) = $sth->fetchrow_array();

    # Construct request
    my $request = {
        credentials => {
            subject => {
                subjectType => 'CapitaPortal',
                identifier  => $Pay360PortalID,
                systemCode  => 'SCP'
            },
            requestIdentification => {
                uniqueReference => $requestGUID,
                timeStamp       => $timeStamp
            },
            signature => {
                algorithm => 'Original',
                hmacKeyID => $Pay360HMACID,
                digest    => $currentDigest
            },
        },
        siteId       => $Pay360SiteID,
        scpReference => $scpReference
    };

    my $portal = $self->retrieve_data('Pay360Portal');
    my $scpSimpleQuery = $wsdl->compileClient( operation => 'scpSimpleQuery' );

    my $response = $scpSimpleQuery->($request);

    # Handle errors
    if (
        exists(
            $response->{'scpSimpleQueryResponse'}->{'paymentResult'}
              ->{'errorDetails'}
        )
      )
    {
        use Data::Dumper;
        warn Dumper( $response->{'scpSimpleQueryResponse'}->{'paymentResult'}
              ->{'errorDetails'} );
    }

    # Sucess
    else {

        my $saleSummary =
          $response->{'scpSimpleQueryResponse'}->{'paymentResult'}
          ->{'paymentDetails'}->{'saleSummary'};
        use Data::Dumper;
        warn Dumper($response);
        my @accountline_ids =
          map { $_->{'lineId'} } @{ $saleSummary->{'items'}->{'itemSummary'} };

        # Record Payment
        my $borrower = Koha::Patrons->find($borrowernumber);
        my $lines    = Koha::Account::Lines->search(
            { accountlines_id => { 'in' => \@accountline_ids } } )->as_list;
        my $totalpaid = 0;
        for my $line ( @{$lines} ) {
            my $amount = sprintf "%.2f", $line->amountoutstanding;
            $amount    = $amount * 100;
            $totalpaid = $totalpaid + $amount;
        }
        $totalpaid = $totalpaid / 100;
        my $account = Koha::Account->new( { patron_id => $borrowernumber } );
        my $accountline_id = $account->pay(
            {
                amount     => $totalpaid,
                note       => 'Pay360 Payment',
                library_id => $borrower->branchcode,
                lines      => $lines,
            }
        );

        # Link payment to pay360_transactions
        my $sth = $dbh->prepare(
            "UPDATE $table SET accountline_id = ? WHERE transaction_guid = ?");
        $sth->execute( $accountline_id, $transactionGUID );

        # Renew any items as required
        for my $line ( @{$lines} ) {
            my $item = Koha::Items->find( { itemnumber => $line->itemnumber } );

            # Renew if required
            if ( defined( $line->accounttype )
                && $line->accounttype eq "FU" )
            {
                if (
                    C4::Circulation::CheckIfIssuedToPatron(
                        $line->borrowernumber, $item->biblionumber
                    )
                  )
                {
                    my ( $can, $error ) =
                      C4::Circulation::CanBookBeRenewed( $line->borrowernumber,
                        $line->itemnumber, 0 );
                    if ($can) {

                        my $datedue =
                          C4::Circulation::AddRenewal( $line->borrowernumber,
                            $line->itemnumber );
                        C4::Circulation::_FixOverduesOnReturn(
                            $line->borrowernumber, $line->itemnumber );
                    }
                }
            }
        }

        # Output result
        if ( defined($totalpaid) ) {
            $totalpaid = sprintf "%.2f", $totalpaid;
            $template->param(
                borrower      => scalar Koha::Patrons->find($borrowernumber),
                message       => 'valid_payment',
                message_value => $totalpaid
            );
        }
        else {
            $template->param(
                borrower => scalar Koha::Patrons->find($borrowernumber),
                message  => 'no_amount'
            );
        }

        print $cgi->header();
        print $template->output();
    }
}

=head2 configure

  Configuration routine
  
=cut

sub configure {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    unless ( $cgi->param('save') ) {
        my $template = $self->get_template( { file => 'configure.tt' } );

        ## Grab the values we already have for our settings, if any exist
        $template->param(
            enable_opac_payments =>
              $self->retrieve_data('enable_opac_payments'),
            Pay360SiteID   => $self->retrieve_data('Pay360SiteID'),
            Pay360HMAC     => $self->retrieve_data('Pay360HMAC'),
            Pay360Portal   => $self->retrieve_data('Pay360Portal'),
            Pay360PortalID => $self->retrieve_data('Pay360PortalID'),
            Pay360HMACID   => $self->retrieve_data('Pay360HMACID'),
        );

        print $cgi->header();
        print $template->output();
    }
    else {
        $self->store_data(
            {
                enable_opac_payments => $cgi->param('enable_opac_payments'),
                Pay360SiteID         => $cgi->param('Pay360SiteID'),
                Pay360Portal         => $cgi->param('Pay360Portal'),
                Pay360PortalID       => $cgi->param('Pay360PortalID'),
                Pay360HMACID         => $cgi->param('Pay360HMACID'),
                Pay360HMAC           => $cgi->param('Pay360HMAC'),
                last_configured_by   => C4::Context->userenv->{'number'},
            }
        );
        $self->go_home();
    }
}

## This is the 'install' method. Any database tables or other setup that should
## be done when the plugin if first installed should be executed in this method.
## The installation method should always return true if the installation succeeded
## or false if it failed.
sub install() {
    my ( $self, $args ) = @_;

    my $table = $self->get_qualified_table_name('pay360_transactions');

    return C4::Context->dbh->do( "
        CREATE TABLE IF NOT EXISTS $table (
            `transaction_id` INT( 11 ) NOT NULL AUTO_INCREMENT,
            `transaction_guid` varchar(36) NOT NULL,
            `transaction_reference` TINYTEXT,
            `transaction_state` TINYTEXT,
            `accountline_id` INT( 11 ),
            `updated` TIMESTAMP,
            PRIMARY KEY (`transaction_id`)
        ) ENGINE = INNODB;
    " );
}

=head2 get_digest

  Internal routine for generating the signature digest for messages

=cut

sub get_digest {
    my $self = shift;
    my (
        $subjectType, $identifier, $uniqueReference,
        $timestamp,   $algorithm,  $Pay360HMACID
    ) = @_;

    my @set = (
        $subjectType, $identifier, $uniqueReference,
        $timestamp,   $algorithm,  $Pay360HMACID
    );
    my $Pay360HMAC = $self->retrieve_data('Pay360HMAC');

    my $data   = join( '!', @set );
    my $key    = b64_decode($Pay360HMAC);
    my $digest = hmac_sha256_base64( $data, $key );
    while ( length($digest) % 4 ) {
        $digest .= '=';
    }

    if ($debug) {
        warn "HmacKey: " . $Pay360HMAC;
        warn "HmacKeyId: " . $Pay360HMACID;
        warn "Subject Type: " . $subjectType;
        warn "Identifier: " . $identifier;
        warn "Unique Reference: " . $uniqueReference;
        warn "Algorithm: " . $algorithm;
        warn "Timestamp: " . $timestamp;
        warn "String to hash: " . $data;
        warn "Digest: " . $digest;
    }

    return $digest;
}

## This is the 'upgrade' method. It will be triggered when a newer version of a
## plugin is installed over an existing older version of a plugin
#sub upgrade {
#    my ( $self, $args ) = @_;
#
#    my $dt = dt_from_string();
#    $self->store_data(
#        { last_upgraded => $dt->ymd('-') . ' ' . $dt->hms(':') } );
#
#    return 1;
#}

## This method will be run just before the plugin files are deleted
## when a plugin is uninstalled. It is good practice to clean up
## after ourselves!
#sub uninstall() {
#    my ( $self, $args ) = @_;
#
#    my $table = $self->get_qualified_table_name('mytable');
#
#    return C4::Context->dbh->do("DROP TABLE $table");
#}

1;
