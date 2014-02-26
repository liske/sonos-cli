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
use HTTP::Status qw(:constants status_message);
use Log::Any;
use Socket;

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
    sonos_config_register(qq(SONOS/SearchTimeout), qr/^\d+/, 0, 3);
    sonos_config_register(qq(SONOS/BackendPort), qr/^\d+/, 0, 1401);
}

sub new {
    my ($class) = @_;
    my $self = $class->SUPER::new();

    $self->{_sonos}->{logger} = Log::Any->get_logger(category => __PACKAGE__);
    $self->{_sonos}->{speak} = Net::UPnP::SONOS::Speak->new;
    $self->{_sonos}->{search_timeout} = sonos_config_get(qq(SONOS/SearchTimeout));
    $self->{_sonos}->{sid2dev} = { };
    $self->{_sonos}->{httpd} = AnyEvent::HTTPD->new(
	allowed_methods => [qw(NOTIFY GET)],
	port => sonos_config_get(qq(SONOS/BackendPort)),
	);
    $self->{_sonos}->{httpd}->reg_cb (
	request => sub {
	    my ($httpd, $req) = @_;
	    my $headers = $req->headers;

	    if($req->method eq qq(NOTIFY)) {
		my $sid = (exists($headers->{sid}) ? $headers->{sid} : '');

		unless(exists($self->{_sonos}->{sid2dev}->{$sid})) {
		    my $msg = "rejecting unknown subscription '$sid'";
		    $self->{_sonos}->{logger}->notice($msg);
		    $req->respond([412, 'Precondition Failed', { 'Content-Type' => 'text/plain' }, $msg]);
		    
		    return;
		}
		$req->respond([HTTP_OK, status_message(HTTP_OK), { 'Content-Type' => 'text/plain' }, 'OK']);

		$self->{_sonos}->{sid2dev}->{$sid}->handleNotify($sid, $req->content);
	    }
	    elsif($req->method eq qq(GET)) {
		my @path = $req->url->path_segments;
		shift(@path);

		if($path[0] eq qq(speak)) {
		    my $digest = pop(@path);

		    my $fh = $self->{_sonos}->{speak}->open($digest);
		    if(defined($fh)) {
			$req->respond ({ content => ['audio/mpeg', do { local $/; <$fh> }] });
		    }
		    else {
			$req->respond([HTTP_NOT_FOUND, status_message(HTTP_NOT_FOUND), { 'Content-Type' => 'text/plain' }, "Digest unknown: $digest"]);
		    }
		}
		else {
		    $req->respond([HTTP_BAD_REQUEST, status_message(HTTP_BAD_REQUEST), { 'Content-Type' => 'text/plain' }, "Unknown request: $path[0]"]);
		}
	    }
	    else {
		$req->respond([HTTP_INTERNAL_SERVER_ERROR, status_message(HTTP_INTERNAL_SERVER_ERROR), { 'Content-Type' => 'text/plain' }, 'Method unavailable: '.$req->method]);
	    }
	},);
    $self->{_sonos}->{logger}->notice("listening on ".$self->{_sonos}->{httpd}->host.":".$self->{_sonos}->{httpd}->port."...");

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

sub search {
    die;
    my $self = shift;
    $self->{_sonos}->{zones} = undef;
    $self->{_sonos}->{groups} = undef;

    my @zps = $self->SUPER::search(st => 'urn:schemas-upnp-org:device:ZonePlayer:1', mx => $self->{_sonos}->{search_timeout});
    foreach my $zp (@zps) {
	my %services;
	$services{(SONOS_SRV_AlarmClock)} = $zp->getservicebyname(SONOS_SRV_AlarmClock);
	$services{(SONOS_SRV_DeviceProperties)} = $zp->getservicebyname(SONOS_SRV_DeviceProperties);
	$services{(SONOS_SRV_AVTransport)} = $zp->getservicebyname(SONOS_SRV_AVTransport);
	
	
# GetZoneInfo (get MACAddress to build UDN)
# HACK: $zp->getudn() is broken, try to build the UDN
#       from the MACAddress - this might fail :-(
	my $aresp = $services{(SONOS_SRV_DeviceProperties)}->postaction('GetZoneInfo');
	if($aresp->getstatuscode != SONOS_STATUS_OK) {
	    carp 'Got error code '.$aresp->getstatuscode;
	    next;
	}
	my $ZoneInfo = $aresp->getargumentlist;
	my $UDN = $ZoneInfo->{MACAddress};
	$UDN =~ s/://g;
	$UDN = "RINCON_${UDN}01400";
	
	$self->{_sonos}->{zones}->{$UDN}->{zone} = $zp;
	$self->{_sonos}->{zones}->{$UDN}->{services} = \%services;
	$self->{_sonos}->{zones}->{$UDN}->{ZoneInfo} = $ZoneInfo;
	

# GetZoneAttributes (get zone name)
	$aresp = $services{(SONOS_SRV_DeviceProperties)}->postaction('GetZoneAttributes');
	if($aresp->getstatuscode != SONOS_STATUS_OK) {
	    carp 'Got error code '.$aresp->getstatuscode;
	    next;
	}
	$self->{_sonos}->{zones}->{$UDN}->{ZoneAttributes} = $aresp->getargumentlist;

	
	my %aargs = (
	    'InstanceID' => 0,
	    );
	
	$aresp = $services{(SONOS_SRV_AVTransport)}->postaction('GetPositionInfo', \%aargs);
	if($aresp->getstatuscode != SONOS_STATUS_OK) {
	    carp 'Got error code '.$aresp->getstatuscode;
	    next;
	}
	$self->{_sonos}->{zones}->{$UDN}->{PositionInfo} = $aresp->getargumentlist;
	
	
	$aresp = $services{(SONOS_SRV_AVTransport)}->postaction('GetTransportInfo', \%aargs);
	if($aresp->getstatuscode != SONOS_STATUS_OK) {
	    carp 'Got error code '.$aresp->getstatuscode;
	    next;
	}
	$self->{_sonos}->{zones}->{$UDN}->{TransportInfo} = $aresp->getargumentlist;
    }
}

sub search_async {
    my $self = shift;
    my %args = (
	iv => 0,
	@_,
	);

    $self->{_sonos}->{logger}->debug("search_async(iv = %ds", $args{iv});
    $self->search_async_once(%args);
    $self->{_sonos}->{search}->{iv} = AnyEvent->timer(
	after => $args{iv},
	interval => $args{iv},
	cb => sub {
	    $self->search_async_once(%args);
	},
    ) if($args{iv} > 0);
}

sub search_async_term {
    my $self = shift;

    $self->{_sonos}->{logger}->debug("terminating search_async");
    $self->{_sonos}->{search}->{iv} = undef;
}

sub search_async_once {
    my $self = shift;
    my %args = (
	st => 'urn:schemas-upnp-org:device:ZonePlayer:1',
	mx => $self->{_sonos}->{search_timeout},
	cb => undef,
	@_,
    );
		
    $self->{_sonos}->{logger}->debug("begin async search...");

my $ssdp_header = <<"SSDP_SEARCH_MSG";
M-SEARCH * HTTP/1.1
Host: $Net::UPnP::SSDP_ADDR:$Net::UPnP::SSDP_PORT
Man: "ssdp:discover"
ST: $args{st}
MX: $args{mx}

SSDP_SEARCH_MSG

    $ssdp_header =~ s/\r//g;
    $ssdp_header =~ s/\n/\r\n/g;

    my $ssdp_sock;
    socket($ssdp_sock, AF_INET, SOCK_DGRAM, getprotobyname('udp'));
    my $ssdp_mcast = sockaddr_in($Net::UPnP::SSDP_PORT, inet_aton($Net::UPnP::SSDP_ADDR));
    send($ssdp_sock, $ssdp_header, 0, $ssdp_mcast);

    $self->{_sonos}->{search}->{io} = AnyEvent->io(fh => $ssdp_sock, poll => 'r', cb => sub {
	my $ssdp_res_msg;
	recv($ssdp_sock, $ssdp_res_msg, 4096, 0);

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
    });
    $self->{_sonos}->{search}->{timer} = AnyEvent->timer(after => ($args{mx} + 1), cb => sub {
	$self->{_sonos}->{logger}->info("finished async search");

	# drop watchers
	$self->{_sonos}->{search}->{io} = undef;
	$self->{_sonos}->{search}->{timer} = undef;

	# call callback
	&{$args{cb}}($self) if(defined($args{cb}));
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
