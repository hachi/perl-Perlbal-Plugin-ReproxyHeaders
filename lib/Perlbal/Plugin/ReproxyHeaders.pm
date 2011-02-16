package Perlbal::Plugin::ReproxyHeaders;

use 5.006;

use strict;
use warnings;

use Perlbal;

our $VERSION = "0.00_01";
$VERSION = eval $VERSION;

sub load {
    my $class = shift;

    Perlbal::register_global_hook('manage_command.reproxy_header', sub {
        my $mc = shift->parse(qr/^reproxy_header\s+(?:(\w+)\s+)?(\S+)\s+(PASS|COPY|DROP)$/i,
                              "usage: REPROXY_HEADER [<service>] <header name as string or '*'> PASS|COPY|DROP");
        my ($selname, $match, $result) = $mc->args;

        unless ($selname ||= $mc->{ctx}{last_created}) {
            return $mc->err("omitted service name not implied from context");
        }

        my $service = Perlbal->service($selname);
        return $mc->err("Service '$selname' is not a reverse_proxy.")
            unless $service && $service->{role} eq "reverse_proxy";

        my $mungers = $service->{extra_config}->{_reproxy_headers} ||= [];
        $result = uc($result);

        if ($match eq '*') {
            push @$mungers, [ sub { 1 }, $result ];
        } else {
            push @$mungers, [ sub { shift =~ m/\Q$match\E/i }, $result ];
        }

        return $mc->ok;
    });

    return 1;
}

# unload our global commands, clear our service object
sub unload {
    my $class = shift;

    Perlbal::unregister_global_hook('manage_command.reproxy_header');

    return 1;
}

# called when we're being added to a service
sub register {
    my ($class, $svc) = @_;
    $svc->register_hook('ReproxyHeaders', 'backend_response_received', \&backend_response_received);
    return 1;
}

# called when we're no longer active on a service
sub unregister {
    my ($class, $svc) = @_;
    $svc->unregister_hook('ReproxyHeaders', 'backend_response_received');
    return 1;
}

sub backend_response_received {
    my Perlbal::BackendHTTP $self = shift;
    my Perlbal::HTTPHeaders $res_hd = $self->{res_headers};
    my Perlbal::ClientProxy $client = $self->{client};
    my Perlbal::HTTPHeaders $req_hd = $client->{req_headers};

    my $res_headers = $res_hd->headers_list;

    my $rules = $client->{service}->{extra_config}->{_reproxy_headers};

    foreach my $rule (@$rules) {
        my ($match, $result) = @$rule;
        foreach my $header (@$res_headers) {
            next unless $match->($header);
            if ($result eq 'COPY') {
                $req_hd->header($header, $res_hd->header($header));
                $res_hd->header($header, undef);
                $res_headers = $res_hd->headers_list;
            } elsif ($result eq 'DROP') {
                $res_hd->header($header, undef);
                $res_headers = $res_hd->headers_list;
            }
        }
    }

    return 0; # Continue processing in perlbal
}

1;
