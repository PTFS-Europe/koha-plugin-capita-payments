use utf8;

package Koha::Plugin::Com::PTFSEurope::CapitaPayments;

=head1 NAME

Koha::Plugin::Com::PTFSEurope::CapitaPayments

=cut

use Modern::Perl;

use base qw(Koha::Plugins::Base);

use C4::Context;
use C4::Auth;
use Koha::Account;
use Koha::Account::Lines;
use Koha::Patrons;

use XML::LibXML;
use Mojo::Util qw(b64_decode);
use Digest::SHA qw(hmac_sha256_base64);
use Time::Moment;

use Koha::Plugin::Com::PTFSEurope::CapitaPayments::scpService
  qw(scpSimpleInvoke);

## Here we set our plugin version
our $VERSION = "00.00.01";

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

# A local useragent
our $scpService =
  Koha::Plugin::Com::PTFSEurope::CapitaPayments::scpService->new;

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

    my ( $template, $borrowernumber ) = get_template_and_user(
        {
            template_name   => $self->mbf_path('opac_online_payment_begin.tt'),
            query           => $cgi,
            type            => 'opac',
            authnotrequired => 0,
            is_plugin       => 1,
        }
    );

    # Get the borrower
    my $borrower_result = Koha::Patrons->find($borrowernumber);

    # Create a transaction
    my $dbh   = C4::Context->dbh;
    my $table = $self->get_qualified_table_name('pay360_transactions');
    my $sth = $dbh->prepare("INSERT INTO $table (`transaction_id`) VALUES (?)");
    $sth->execute("NULL");

    my $transaction_id =
      $dbh->last_insert_id( undef, undef,
        qw(pay360_transactions transaction_id) );

    # Construct redirect URI
    my $redirect = C4::Context->preference('OPACBaseURL')
      . "/cgi-bin/koha/opac-account-pay-return.pl";
    my $redirect_url = URI->new($redirect);
    $redirect_url->query_form(
        {
            payment_method => scalar $cgi->param('payment_method'),
            transaction_id => $transaction_id
        }
    );

    # Construct callback URI
    my $callback_url =
        C4::Context->preference('OPACBaseURL')
      . $self->get_plugin_http_path()
      . "/callback.pl";

    # Construct cancel URI
    my $cancel_url =
      C4::Context->preference('OPACBaseURL') . "/cgi-bin/koha/opac-account.pl";

    # Add Credentials
    #################
    my $Pay360SiteID = $self->retrieve_data('Pay360SiteID');
    my $Pay360HMACID = $self->retrieve_data('Pay360HMACID');
    my $reqRef       = $transaction_id;
    my $stamp        = Time::Moment->now_utc->strftime('%Y%m%d%H%M%S');
    my $current_digest =
      $self->get_digest( 'CapitaPortal', $Pay360SiteID, $reqRef, $stamp,
        'Original', $Pay360HMACID );

    my $Pay360PortalID = $self->retrieve_data('Pay360PortalID');

    # items
    my $sum_amountInMinorUnits = 0;
    my @accountline_ids        = $cgi->multi_param('accountline');
    my $accountlines           = $schema->resultset('Accountline')
      ->search( { accountlines_id => \@accountline_ids } );
    my @items;
    my @items_SOAP;
    for my $accountline ( $accountlines->all ) {
        my $amount = sprintf "%.2f", $accountline->amountoutstanding;
        $amount                 = $amount * 100;
        $sum_amountInMinorUnits = $sum_amountInMinorUnits + $amount;

        my $item = {
            itemSummary => {
                description          => $accountline->description,
                amountInMinorUnits   => $amount,
                reference            => $accountline->accountlines_id,
                displayableReference => $accountline->accountlines_id,
            },
            quantity => 1,
            lineId   => $accountline->accountlines_id,
        };
        push @items, $item;

        # SOAP::Lite
        my $item_SOAP = SOAP::Data->name(
            "item" => \SOAP::Data->value(
                SOAP::Data->name(
                    "itemSummary" => \SOAP::Data->value(
                        SOAP::Data->name(
                            "description" => $accountline->description
                        ),
                        SOAP::Data->name( "amountInMinorUnits" => $amount ),
                        SOAP::Data->name(
                            "reference" => $accountline->accountlines_id
                        ),
                        SOAP::Data->name(
                            "displayableReference" =>
                              $accountline->accountlines_id
                        ),
                    ),
                )->uri('http://www.capita-software-services.com/scp/base')
                  ->prefix('scpbase'),
                SOAP::Data->name( "quantity" => 1 )
                  ->uri('http://www.capita-software-services.com/scp/base')
                  ->prefix('scpbase'),
                SOAP::Data->name(
                    "lineId" => $accountline->accountlines_id
                )->uri('http://www.capita-software-services.com/scp/base')
                  ->prefix('scpbase'),
            ),
        )->uri('http://www.capita-software-services.com/scp/simple')
          ->prefix('simple');
        push @items_SOAP, $item_SOAP;
    }

    my $portal = $self->retrieve_data('Pay360Portal');

    # Construct SOAP POST
    my $scpSimpleInvoke = SOAP::Data->name(
        'scpSimpleInvokeRequest' => \SOAP::Data->value(
            SOAP::Data->name(
                "credentials" => \SOAP::Data->value(
                    SOAP::Data->name(
                        "subject" => \SOAP::Data->value(
                            SOAP::Data->name( "subjectType" => 'CapitaPortal' ),
                            SOAP::Data->name( "identifier"  => $Pay360SiteID ),
                            SOAP::Data->name( "systemCode"  => 'SCP' ),
                        ),
                    ),
                ),
                SOAP::Data->name(
                    "requestIdentification" => \SOAP::Data->value(
                        SOAP::Data->name(
                            "uniqueReference" => $transaction_id
                        ),
                        SOAP::Data->name( "timeStamp" => $stamp ),
                    ),
                ),
                SOAP::Data->name(
                    "signature" => \SOAP::Data->value(
                        SOAP::Data->name( "algorithm" => 'Original' ),
                        SOAP::Data->name( "hmacKeyID" => $Pay360HMACID ),
                        SOAP::Data->name( "digest"    => $current_digest ),
                    ),
                ),
            )->uri(
'https://support.capita-software.co.uk/selfservice/?commonFoundation'
            ),
            SOAP::Data->name( "requestType" => 'payOnly' )
              ->uri('http://www.capita-software-services.com/scp/base')
              ->prefix('scpbase'),
            SOAP::Data->name( "requestId" => $transaction_id )
              ->uri('http://www.capita-software-services.com/scp/base')
              ->prefix('scpbase'),
            SOAP::Data->name(
                "routing" => \SOAP::Data->value(
                    SOAP::Data->name( "returnUrl" => $callback_url )
                      ->uri('http://www.capita-software-services.com/scp/base')
                      ->prefix('scpbase'),
                    SOAP::Data->name( "backUrl" => $cancel_url )
                      ->uri('http://www.capita-software-services.com/scp/base')
                      ->prefix('scpbase'),
                    SOAP::Data->name( "siteId" => $Pay360SiteID )
                      ->uri('http://www.capita-software-services.com/scp/base')
                      ->prefix('scpbase'),
                    SOAP::Data->name( "scpId" => $Pay360PortalID )
                      ->uri('http://www.capita-software-services.com/scp/base')
                      ->prefix('scpbase'),
                ),
            )->uri('http://www.capita-software-services.com/scp/base')
              ->prefix('scpbase'),
            SOAP::Data->name( "panEntryMethod" => 'ECOM' )
              ->uri('http://www.capita-software-services.com/scp/base')
              ->prefix('scpbase'),
            SOAP::Data->name(
                "sale" => \SOAP::Data->value(
                    SOAP::Data->name(
                        "saleSummary" => \SOAP::Data->value(
                            SOAP::Data->name(
                                "description" => 'Library Payment'
                            )->uri(
'http://www.capita-software-services.com/scp/base'
                            )->prefix('scpbase'),
                            SOAP::Data->name(
                                "amountInMinorUnits" => $sum_amountInMinorUnits
                            )->uri(
'http://www.capita-software-services.com/scp/base'
                            )->prefix('scpbase'),
                        ),
                      )
                      ->uri('http://www.capita-software-services.com/scp/base')
                      ->prefix('scpbase'),
                    SOAP::Data->name( "items" => @items_SOAP )->uri(
                        'http://www.capita-software-services.com/scp/simple')
                      ->prefix('simple'),
                ),
            )->uri('http://www.capita-software-services.com/scp/simple')
              ->prefix('simple'),
        ),
    )->uri('http://www.capita-software-services.com/scp/simple')
      ->prefix('simple');

    #    $scpSimpleInvoke = SOAP::Data->value(
    #        SOAP::Data->name(
    #            "credentials" => \SOAP::Data->name(
    #                "subject" => \SOAP::Data->value(
    #                    SOAP::Data->name( "subjectType" => 'CapitaPortal' ),
    #                    SOAP::Data->name( "identifier"  => $Pay360SiteID ),
    #                    SOAP::Data->name( "systemCode"  => 'SCP' ),
    #                ),
    #            ),
    #            SOAP::Data->name(
    #                "requestIdentification" => \SOAP::Data->value(
    #                    SOAP::Data->name(
    #                        "uniqueReference" => $transaction_id
    #                    ),
    #                    SOAP::Data->name( "timeStamp" => $stamp ),
    #                ),
    #            ),
    #            SOAP::Data->name(
    #                "signature" => \SOAP::Data->value(
    #                    SOAP::Data->name( "algorithm" => 'Original' ),
    #                    SOAP::Data->name( "hmacKeyID" => $Pay360HMACID ),
    #                    SOAP::Data->name( "digest"    => $current_digest ),
    #                ),
    #            ),
    #        ),
    #        SOAP::Data->name( "requestType" => 'payOnly' ),
    #        SOAP::Data->name( "requestId"   => $transaction_id ),
    #        SOAP::Data->name(
    #            "routing" => \SOAP::Data->value(
    #                SOAP::Data->name( "returnUrl" => $callback_url ),
    #                SOAP::Data->name( "backUrl"   => $cancel_url ),
    #                SOAP::Data->name( "siteId"    => $Pay360SiteID ),
    #                SOAP::Data->name( "scpId"     => $Pay360PortalID ),
    #            ),
    #        ),
    #        SOAP::Data->name( "panEntryMethod" => 'ECOM' ),
    #        SOAP::Data->name(
    #            "sale" => \SOAP::Data->value(
    #                SOAP::Data->name(
    #                    "saleSummary" => \SOAP::Data->value(
    #                        SOAP::Data->name(
    #                            "description" => 'Library Payment'
    #                        ),
    #                        SOAP::Data->name(
    #                            "amountInMinorUnits" => $sum_amountInMinorUnits
    #                        ),
    #                    ),
    #                ),
    #                SOAP::Data->name( "items" => @items_SOAP ),
    #            ),
    #        ),
    #    );

    my $soap_hash = {
        credentials => {
            subject => {
                subjectType => 'CapitaPortal',
                identifier  => $Pay360SiteID,
                systemCode  => 'SCP'
            },
            requestIdentification => {
                uniqueReference => $transaction_id,
                timeStamp       => $stamp
            },
            signature => {
                algorithm => 'Original',
                hmacKeyID => $Pay360HMACID,
                digest    => $current_digest
            },
            requestType => 'payOnly',
            requestId   => $transaction_id,
            routing     => {
                returnUrl => $callback_url,
                backUrl   => $cancel_url,
                siteId    => $Pay360SiteID,
                scpId     => $Pay360PortalID,
            },
            panEntryMethod => 'ECOM',
            sale           => {
                saleSummary => {
                    description        => 'Library Payment',
                    amountInMinorUnits => $sum_amountInMinorUnits,
                },
                items => \@items
            }
        }
    };

    warn "before scpSimpleInvoke";
    my $result = $scpService->scpSimpleInvoke($scpSimpleInvoke);
    use Data::Dumper;
    warn $result;
    warn "after scpSimpleInvoke";

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

    my $transaction_id = $cgi->param('transaction_id');

    # Check payment went through here
    my $table = $self->get_qualified_table_name('pay360_transactions');
    my $dbh   = C4::Context->dbh;
    my $sth   = $dbh->prepare(
        "SELECT accountline_id FROM $table WHERE transaction_id = ?");
    $sth->execute($transaction_id);
    my ($accountline_id) = $sth->fetchrow_array();

    my $line =
      Koha::Account::Lines->find( { accountlines_id => $accountline_id } );
    my $transaction_value = $line->amount;
    my $transaction_amount = sprintf "%.2f", $transaction_value;
    $transaction_amount =~ s/-//g;

    if ( defined($transaction_value) ) {
        $template->param(
            borrower      => scalar Koha::Patrons->find($borrowernumber),
            message       => 'valid_payment',
            message_value => $transaction_amount
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

    my $data   = join( '!', @_ );
    my $key    = b64_decode( $self->retrieve_data('Pay360HMAC') );
    my $digest = hmac_sha256_base64( $data, $key );
    while ( length($digest) % 4 ) {
        $digest .= '=';
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
