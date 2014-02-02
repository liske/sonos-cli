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
use Log::Any;
use Socket;

use strict;
use warnings;
use Carp;

use Net::UPnP::SONOS::Properties qw(:keys);
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

sub new {
    my ($class) = @_;
    my $self = $class->SUPER::new();

    $self->{_sonos}->{logger} = Log::Any->get_logger(category => __PACKAGE__);
    $self->{_sonos}->{search_timeout} = 3;
    $self->{_sonos}->{sid2dev} = { };
    $self->{_sonos}->{httpd} = AnyEvent::HTTPD->new(allowed_methods => [qw(NOTIFY)]);
    $self->{_sonos}->{httpd}->reg_cb (
	request => sub {
	    my ($httpd, $req) = @_;
	    my $headers = $req->headers;
	    my $sid = (exists($headers->{sid}) ? $headers->{sid} : '');

	    unless(exists($self->{_sonos}->{sid2dev}->{$sid})) {
		my $msg = "rejecting unknown subscription '$sid'";
		$self->{_sonos}->{logger}->notice($msg);
		$req->respond([412, 'Precondition Failed', { 'Content-Type' => 'text/plain' }, $msg]);

		return;
	    }
	    $req->respond([200, 'OK', { 'Content-Type' => 'text/plain' }, 'OK']);

	    $self->{_sonos}->{sid2dev}->{$sid}->handleNotify($sid, $req->content);
	},);
    $self->{_sonos}->{logger}->notice("listening on ".$self->{_sonos}->{httpd}->host.":".$self->{_sonos}->{httpd}->port."...");

    bless $self, $class;
    return $self;
}


sub search {
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

	$self->{_sonos}->{search}->{zps}->{$zpid} = $dev;
    });
    $self->{_sonos}->{search}->{timer} = AnyEvent->timer(after => ($args{mx} + 1), cb => sub {
	$self->{_sonos}->{logger}->info("finished async search");

	# drop watchers
	$self->{_sonos}->{search}->{io} = undef;
	$self->{_sonos}->{search}->{timer} = undef;


	$self->{_sonos}->{zones} = undef;
	$self->{_sonos}->{groups} = undef;

	foreach my $zpid (keys %{$self->{_sonos}->{search}->{zps}}) {
	    my $zp = $self->{_sonos}->{search}->{zps}->{$zpid};
	    my %services;
	    $services{(SONOS_SRV_AlarmClock)} = $zp->getservicebyname(SONOS_SRV_AlarmClock);
	    $services{(SONOS_SRV_DeviceProperties)} = $zp->getservicebyname(SONOS_SRV_DeviceProperties);
	    $services{(SONOS_SRV_AVTransport)} = $zp->getservicebyname(SONOS_SRV_AVTransport);

	    # GetZoneAttributes (get zone name)
	    my $aresp = $services{(SONOS_SRV_DeviceProperties)}->postaction('GetZoneAttributes');
	    if($aresp->getstatuscode != SONOS_STATUS_OK) {
		carp 'Got error code '.$aresp->getstatuscode;
		next;
	    }
	    $self->{_sonos}->{zones}->{$zpid}->{ZoneAttributes} = $aresp->getargumentlist;


	    my %aargs = (
		'InstanceID' => 0,
	    );


	    $aresp = $services{(SONOS_SRV_AVTransport)}->postaction('GetPositionInfo', \%aargs);
	    if($aresp->getstatuscode != SONOS_STATUS_OK) {
		carp 'Got error code '.$aresp->getstatuscode;
		next;
	    }
	    $self->{_sonos}->{zones}->{$zpid}->{PositionInfo} = $aresp->getargumentlist;


	    $aresp = $services{(SONOS_SRV_AVTransport)}->postaction('GetTransportInfo', \%aargs);
	    if($aresp->getstatuscode != SONOS_STATUS_OK) {
		carp 'Got error code '.$aresp->getstatuscode;
		next;
	    }
	    $self->{_sonos}->{zones}->{$zpid}->{TransportInfo} = $aresp->getargumentlist;

	    if($self->{_sonos}->{zones}->{$zpid}->{PositionInfo}->{TrackURI} =~ /^x-rincon:(RINCON_[\dA-F]+)/) {
		push(@{$self->{_sonos}->{groups}->{$1}}, $zpid);
	    }
	    else {
		push(@{$self->{_sonos}->{groups}->{$zpid}}, $zpid);
	    }
	}

	&{$args{cb}}($self) if(defined($args{cb}));
    });
}

sub regSrvSubs($$$) {
    my ($self, $sid, $dev) = @_;

    $self->{_sonos}->{sid2dev}->{$sid} = $dev;
};

sub getZones {
    my $self = shift;
    $self->search() unless(exists($self->{_sonos}->{zones}) && defined($self->{_sonos}->{zones}));
    
    return ( ) unless(exists($self->{_sonos}->{zones}) && defined($self->{_sonos}->{zones}));

    return %{$self->{_sonos}->{zones}};
}

sub getGroups {
    my $self = shift;
    $self->search() unless(exists($self->{_sonos}->{zones}) && defined($self->{_sonos}->{zones}));
    
    return ( ) unless(exists($self->{_sonos}->{zones}) && defined($self->{_sonos}->{zones}));

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

1;
