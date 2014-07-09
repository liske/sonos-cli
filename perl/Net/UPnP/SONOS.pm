# sonos-cli - Command line interface to control 'Sonos ZonePlayer' 
#
# Authors:
#   Thomas Liske <thomas@fiasko-nw.net>
#
# Copyright Holder:
#   2010 - 2013 (C) Thomas Liske [http://fiasko-nw.net/~thomas/]
#
# License:
#   This program is free software; you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation; either version 2 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this package; if not, write to the Free Software
#   Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301 USA
#

package Net::UPnP::SONOS;

use AnyEvent;
use AnyEvent::HTTPD;
use AnyEvent::Handle::UDP;
use HTTP::Status qw(:constants status_message);
use Log::Any;
use Socket;
use IO::Socket::Multicast;

use strict;
use warnings;
use Carp;

use Net::UPnP::SONOS::Config;
use Net::UPnP::SONOS::Properties qw(:keys);
use Net::UPnP::SONOS::Speak;
use Net::UPnP::SONOS::ZonePlayer;

use constant {
    SONOS_STATUS_OK => 200,

    SONOS_SRV_AlarmClock => 'urn:schemas-upnp-org:service:AlarmClock:1',
    SONOS_SRV_DeviceProperties => 'urn:schemas-upnp-org:service:DeviceProperties:1',
    SONOS_SRV_AVTransport => 'urn:schemas-upnp-org:service:AVTransport:1',
};

use Net::UPnP::ControlPoint;
require Exporter;
our @ISA = qw(Net::UPnP::ControlPoint Exporter);

our @EXPORT = qw(
    SONOS_STATUS_OK
    SONOS_SRV_AlarmClock
    SONOS_SRV_DeviceProperties
    SONOS_SRV_AVTransport
);

our $VERSION = '0.1.0';

BEGIN {
    sonos_config_register(qq(SONOS/BackendPort), qr/^\d+$/, qq(Backend HTTP port used for event registration.), 0, 1401);
}

sub new {
    my ($class) = @_;
    my $self = $class->SUPER::new();

    $self->{_sonos}->{logger} = Log::Any->get_logger(category => __PACKAGE__);
    $self->{_sonos}->{speak} = Net::UPnP::SONOS::Speak->new;
    $self->{_sonos}->{sid2dev} = { };
    $self->{_sonos}->{httpd} = AnyEvent::HTTPD->new(
	allowed_methods => [qw(NOTIFY GET)],
	port => sonos_config_get(qq(SONOS/BackendPort)),
	);
    $self->{_sonos}->{httpd}->reg_cb (
	request => sub {
	    my ($httpd, $req) = @_;
	    my $headers = $req->headers;
	    my %rheaders = (
		Server => qq(sonos-cli $VERSION),
		);

	    if($req->method eq qq(NOTIFY)) {
		my $sid = (exists($headers->{sid}) ? $headers->{sid} : '');

		$rheaders{q(Content-Type)} = 'text/plain';
		unless(exists($self->{_sonos}->{sid2dev}->{$sid})) {
		    my $msg = "rejecting unknown subscription '$sid'";
		    $self->{_sonos}->{logger}->notice($msg);
		    $req->respond([412, 'Precondition Failed', \%rheaders, $msg]);
		    
		    return;
		}
		$req->respond([HTTP_OK, status_message(HTTP_OK), \%rheaders, 'OK']);

		$self->{_sonos}->{sid2dev}->{$sid}->handleNotify($sid, $req->content);
	    }
	    elsif($req->method eq qq(GET)) {
		my @path = $req->url->path_segments;
		shift(@path);

		if($path[0] eq qq(speak)) {
		    my $digest = pop(@path);

		    my $fh = $self->{_sonos}->{speak}->open($digest);
		    if(defined($fh)) {
			$req->respond([HTTP_OK, status_message(HTTP_OK), { %rheaders, 'Content-Type' => 'audio/mpeg', 'icy-name' => qq(sonos-cli $VERSION), 'icy-pub' => 0 }, do { local $/; <$fh> }]);
		    }
		    else {
			$req->respond([HTTP_NOT_FOUND, status_message(HTTP_NOT_FOUND), { %rheaders, 'Content-Type' => 'text/plain' }, "Digest unknown: $digest"]);
		    }
		}
		else {
		    $req->respond([HTTP_BAD_REQUEST, status_message(HTTP_BAD_REQUEST), { %rheaders, 'Content-Type' => 'text/plain' }, "Unknown request: $path[0]"]);
		}
	    }
	    else {
		$req->respond([HTTP_INTERNAL_SERVER_ERROR, status_message(HTTP_INTERNAL_SERVER_ERROR), { %rheaders, 'Content-Type' => 'text/plain' }, 'Method unavailable: '.$req->method]);
	    }
	},);
    $self->{_sonos}->{logger}->notice("httpd listening on ".$self->{_sonos}->{httpd}->host.":".$self->{_sonos}->{httpd}->port."...");
    $self->{_sonos}->{logger}->notice("ssdp listening on ".$self->{_sonos}->{httpd}->host.":$Net::UPnP::SSDP_PORT...");

    $self->{_sonos}->{msearch_cb} = sub {};
    $self->{_sonos}->{ssdp} = AnyEvent::Handle::UDP->new(
	bind => [ $self->{_sonos}->{httpd}->host, $self->{_sonos}->{httpd}->port ],
	on_recv => sub {
	    my $msg = shift;
	    $msg =~ /^(\S+)\s/;
	    my $method = $1;

	    if($method eq 'HTTP/1.1' &&
	       $msg =~ m/USN: uuid:RINCON_(.+)01400::urn:schemas-upnp-org:device:ZonePlayer:1\r/i) {
	    
		my $zpid = $1;
		unless(exists($self->{_sonos}->{search}->{zps}->{$zpid})) {
		    $self->{_sonos}->{logger}->info("discovered unknown device by SSDP M-SEARCH:", $zpid);

		    # make device identification short time later
		    $self->{_sonos}->{msearch_res}->{$zpid} = $msg;
		    $self->{_sonos}->{msearch_w} = AnyEvent->timer(
			after => 1,
			cb => sub {
			    $self->{_sonos}->{logger}->info('handle', (scalar keys %{ $self->{_sonos}->{msearch_res} }), 'new discovered devices');
			    foreach my $msg (values %{ $self->{_sonos}->{msearch_res} }) {
				$self->extract_ssdp($msg);
			    }
			    $self->{_sonos}->{msearch_res} = {};
			    $self->{_sonos}->{msearch_w} = undef;
			    &{$self->{_sonos}->{msearch_cb}};
			}
		    );
		}
	    }
	    else {
		$self->{_sonos}->{logger}->info('unhandled SSDP message: ', $msg);
	    }
    });

    bless $self, $class;
    return $self;
}

sub httpd {
    my $self = shift;

    return $self->{_sonos}->{httpd};
}

sub speak {
    my $self = shift;

    return $self->{_sonos}->{speak};
}

sub extract_ssdp {
    my $self = shift;
    my $ssdp_res_msg = shift;

    print "$ssdp_res_msg" if ($Net::UPnP::DEBUG);
	
    unless ($ssdp_res_msg =~ m/LOCATION[ :]+(.*)\r/i) {
	$self->{_sonos}->{logger}->info("ignore response missing LOCATION header");
	return;
    }		

    my $dev_location = $1;
    unless ($dev_location =~ m/http:\/\/([0-9a-z.]+)[:]*([0-9]*)\/(.*)/i) {
	$self->{_sonos}->{logger}->info("ignore response due failing to extract location");
	return;
    }

    my $dev_addr = $1;
    my $dev_port = $2;
    my $dev_path = '/' . $3;
	
    my $http_req = Net::UPnP::HTTP->new();
    my $post_res = $http_req->post($dev_addr, $dev_port, "GET", $dev_path, "", "");
	
    my $post_content = $post_res->getcontent();
    unless($post_content =~ /<UDN>uuid:(RINCON_[\dA-F]+)\W/s) {
	print "$post_content\n";
	$self->{_sonos}->{logger}->info("ignore response due failing to extract UDN");
	return
    }
    my $zpid = Net::UPnP::SONOS::ZonePlayer::UDN2ShortID("uuid:$1");
	
    my $dev = ( exists($self->{_sonos}->{search}->{zps}->{$zpid}) ? $self->{_sonos}->{search}->{zps}->{$zpid} : Net::UPnP::SONOS::ZonePlayer->new($self, $self->{_sonos}->{httpd} ) );
    $dev->setssdp($ssdp_res_msg);
    $dev->setdescription($post_content);
    $dev->subEvents($self->{_sonos}->{httpd});
    $dev->init;

    $self->{_sonos}->{search}->{zps}->{$zpid} = $dev;
}

sub search {
    my $self = shift;
    my %args = (
	st => 'urn:schemas-upnp-org:device:ZonePlayer:1',
	mx => 60,
	iv => 1800,
	@_,
    );

    $self->{_sonos}->{msearch_cb} = $args{cb} if(exists($args{cb}));
    $self->{_sonos}->{msearch_iv} = AnyEvent->timer(
	after => 0,
	interval => $args{iv},
	cb => sub {
	    $self->{_sonos}->{logger}->info("begin async search...");

	    my $ssdp_header = <<"SSDP_SEARCH_MSG";
M-SEARCH * HTTP/1.1
Host: $Net::UPnP::SSDP_ADDR:$Net::UPnP::SSDP_PORT
Man: "ssdp:discover"
ST: $args{st}
MX: $args{mx}

SSDP_SEARCH_MSG

            $ssdp_header =~ s/\r//g;
	    $ssdp_header =~ s/\n/\r\n/g;

	    $self->{_sonos}->{ssdp}->push_send($ssdp_header, [ $Net::UPnP::SSDP_ADDR, $Net::UPnP::SSDP_PORT ]);
	});
}

sub regSrvSubs($$$) {
    my ($self, $sid, $dev) = @_;

    $self->{_sonos}->{sid2dev}->{$sid} = $dev;
};

sub getZones {
    my $self = shift;

    return %{$self->{_sonos}->{search}->{zps}};
}

sub getGroups {
    my $self = shift;

    my %groups;
    foreach my $zpid (keys %{$self->{_sonos}->{search}->{zps}}) {
	my $dev = $self->{_sonos}->{search}->{zps}->{$zpid};

	if($dev->getProperty(SONOS_GroupCoordinatorIsLocal)) {
	    foreach my $udn (split(',', $dev->getProperty(SONOS_ZonePlayerUUIDsInGroup))) {
		my $zpid = Net::UPnP::SONOS::ZonePlayer::UDN2ShortID("uuid:$udn");

		push(@{$groups{$dev->getShortID()}}, $self->{_sonos}->{search}->{zps}->{$zpid})
		    if(exists($self->{_sonos}->{search}->{zps}->{$zpid}));
	    }
	}
    }

    return %groups;
}

sub getGroup {
    my $self = shift;
    my $search = shift;

    foreach my $zpid (keys %{$self->{_sonos}->{search}->{zps}}) {
	my $dev = $self->{_sonos}->{search}->{zps}->{$zpid};

	if($dev->getProperty(SONOS_GroupCoordinatorIsLocal)) {
	    foreach my $udn (split(',', $dev->getProperty(SONOS_ZonePlayerUUIDsInGroup))) {
		my $zpid2 = Net::UPnP::SONOS::ZonePlayer::UDN2ShortID("uuid:$udn");

		return $zpid if($zpid2 eq $search);
	    }
	}
    }
   
}

1;
