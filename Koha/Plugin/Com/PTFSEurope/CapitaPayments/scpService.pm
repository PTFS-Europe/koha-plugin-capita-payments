package Koha::Plugin::Com::PTFSEurope::CapitaPayments::scpService;
# Generated by SOAP::Lite (v1.27) for Perl -- soaplite.com
# Copyright (C) 2000-2006 Paul Kulchenko, Byrne Reese
# -- generated at [Tue Nov 20 11:57:40 2018]
# -- generated from https://sbsctest.e-paycapita.com/scp/scpws/scpSimpleClient.wsdl
my %methods = (
'scpSimpleInvoke' => {
    endpoint => 'https://sbsctest.e-paycapita.com/scp/scpws/',
    soapaction => '',
    namespace => 'http://www.capita-software-services.com/scp/simple',
    #    parameters => [
    #  SOAP::Data->new(name => 'scpSimpleInvokeRequest', type => 'scpSimpleInvokeRequest', attr => {}),
    #], # end parameters
  }, # end scpSimpleInvoke
'scpSimpleQuery' => {
    endpoint => 'https://sbsctest.e-paycapita.com:443/scp/scpws',
    soapaction => '',
    namespace => 'http://www.capita-software-services.com/scp/simple',
    parameters => [
      SOAP::Data->new(name => 'scpSimpleQueryRequest', type => 'scpbase:scpQueryRequest', attr => {}),
    ], # end parameters
  }, # end scpSimpleQuery
'scpVersion' => {
    endpoint => 'https://sbsctest.e-paycapita.com:443/scp/scpws',
    soapaction => '',
    namespace => 'http://www.capita-software-services.com/scp/simple',
    parameters => [
      SOAP::Data->new(name => 'scpVersionRequest', type => 'scpVersionRequest', attr => {}),
    ], # end parameters
  }, # end scpVersion
); # end my %methods

use SOAP::Lite;
use Exporter;
use Carp ();

use vars qw(@ISA $AUTOLOAD @EXPORT_OK %EXPORT_TAGS);
@ISA = qw(Exporter SOAP::Lite);
@EXPORT_OK = (keys %methods);
%EXPORT_TAGS = ('all' => [@EXPORT_OK]);

sub _call {
    my ($self, $method) = (shift, shift);
    my $name = UNIVERSAL::isa($method => 'SOAP::Data') ? $method->name : $method;
    my %method = %{$methods{$name}};
    $self->proxy($method{endpoint} || Carp::croak "No server address (proxy) specified")
        unless $self->proxy;
    my @templates = @{$method{parameters}};
    my @parameters = ();
    foreach my $param (@_) {
        warn "param: $param";
        if (@templates) {
            warn "templates";
            my $template = shift @templates;
            my ($prefix,$typename) = SOAP::Utils::splitqname($template->type);
            warn "typename:" . $typename;
            my $method = 'as_'.$typename;
            # TODO - if can('as_'.$typename) {...}
            my $result = $self->serializer->$method($param, $template->name, $template->type, $template->attr);
            warn "result: " . $result;
            push(@parameters, $template->value($result->[2]));
        }
        else {
            warn "passing param as is";
            push(@parameters, $param);
        }
    }
    $self->endpoint($method{endpoint})
       ->ns($method{namespace})
       ->on_action(sub{qq!"$method{soapaction}"!});
  $self->serializer->register_ns("http://www.capita-software-services.com/scp/simple","simple");
  #$self->serializer->register_ns("https://support.capita-software.co.uk/selfservice/?commonFoundation","sch1");
  #$self->serializer->register_ns("http://schemas.xmlsoap.org/wsdl/","wsdl");
  $self->serializer->register_ns("http://www.capita-software-services.com/scp/base","scpbase");
  #$self->serializer->register_ns("http://www.capita-software-services.com/portal-api","sch0");
  warn "calling SUPER::call($method => @parameters)";
    my $serialized = $self->serializer->serialize($parameters[0]);
    warn $serialized;
    my $som = $self->SUPER::call($method => @parameters);
    if ($self->want_som) {
        return $som;
    }
    warn "is SOAP::SOM" if UNIVERSAL::isa($som => 'SOAP::SOM');
    if ($som->fault) { die $som->fault->faultstring };
    use Data::Dumper;
    my $root = $som->root;
    warn Dumper($root);
    warn "SOAP::SOM->result: " .$som->result; 
    UNIVERSAL::isa($som => 'SOAP::SOM') ? wantarray ? $som->paramsall : $som->result : $som;
}

sub BEGIN {
    no strict 'refs';
    for my $method (qw(want_som)) {
        my $field = '_' . $method;
        *$method = sub {
            my $self = shift->new;
            @_ ? ($self->{$field} = shift, return $self) : return $self->{$field};
        }
    }
}
no strict 'refs';
for my $method (@EXPORT_OK) {
    my %method = %{$methods{$method}};
    *$method = sub {
        warn "called $method\n";
        my $self = UNIVERSAL::isa($_[0] => __PACKAGE__)
            ? ref $_[0]
                ? shift # OBJECT
                # CLASS, either get self or create new and assign to self
                : (shift->self || __PACKAGE__->self(__PACKAGE__->new))
            # function call, either get self or create new and assign to self
            : (__PACKAGE__->self || __PACKAGE__->self(__PACKAGE__->new));
        $self->_call($method, @_);
    }
}

sub AUTOLOAD {
    my $method = substr($AUTOLOAD, rindex($AUTOLOAD, '::') + 2);
    return if $method eq 'DESTROY' || $method eq 'want_som';
    die "Unrecognized method '$method'. List of available method(s): @EXPORT_OK\n";
}

1;
