# sonos-cli - Command line interface to control 'Sonos ZonePlayer' 
#
# Authors:
#   Thomas Liske <thomas@fiasko-nw.net>
#
# Copyright Holder:
#   2010 - 2012 (C) Thomas Liske [http://fiasko-nw.net/~thomas/]
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
use Socket;

use strict;
use warnings;
use Carp;

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

    $self->{_sonos}->{search_timeout} = 3;

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

	if($self->{_sonos}->{zones}->{$UDN}->{PositionInfo}->{TrackURI} =~ /^x-rincon:(RINCON_[\dA-F]+)/) {
	    push(@{$self->{_sonos}->{groups}->{$1}}, $UDN);
	}
	else {
	    push(@{$self->{_sonos}->{groups}->{$UDN}}, $UDN);
	}
    }
}

sub search_async {
    my $self = shift;
    my %args = (
	iv => 0,
	@_,
	);
    
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
    $self->{_sonos}->{search}->{iv} = undef;
}

sub search_async_once {
    my $self = shift;
    my %args = (
	st => 'urn:schemas-upnp-org:device:ZonePlayer:1',
	mx => $self->{_sonos}->{search_timeout},
	cb => undef,
	ss => undef,
	@_,
    );
		
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

    if ($Net::UPnP::DEBUG) {
	print "$ssdp_header\n";
    }

    $self->{_sonos}->{search}->{io} = AnyEvent->io(fh => $ssdp_sock, poll => 'r', cb => sub {
	my $ssdp_res_msg;
	recv($ssdp_sock, $ssdp_res_msg, 4096, 0);
	
	print "$ssdp_res_msg" if ($Net::UPnP::DEBUG);
	
	unless ($ssdp_res_msg =~ m/LOCATION[ :]+(.*)\r/i) {
	    return;
	}		

	my $dev_location = $1;
	unless ($dev_location =~ m/http:\/\/([0-9a-z.]+)[:]*([0-9]*)\/(.*)/i) {
	    return;
	}

	my $dev_addr = $1;
	my $dev_port = $2;
	my $dev_path = '/' . $3;
	
	my $http_req = Net::UPnP::HTTP->new();
	my $post_res = $http_req->post($dev_addr, $dev_port, "GET", $dev_path, "", "");
	
	if ($Net::UPnP::DEBUG) {
	    print $post_res->getstatus() . "\n";
	    print $post_res->getheader() . "\n";
	    print $post_res->getcontent() . "\n";
	}
 
	my $post_content = $post_res->getcontent();
	next unless($post_content =~ /<UDN>uuid:[^<]+(RINCON_[\dA-F]+)\W/s);
	my $zpid = $1;
	
	my $dev = Net::UPnP::SONOS::ZonePlayer->new();
	$dev->setssdp($ssdp_res_msg);
	$dev->setdescription($post_content);
	    $dev->subEvents($args{lsip}, 123, $args{lspath} || '');
	if(exists($args{lsport})) {
	    my $lspath = $args{lspath} || '';
	    $lspath =~ s/^[\/]*(.+)[\/]*$/$1/;

	    $dev->subEvents($args{lsip}, 123, $args{lspath} || '');

	    $Net::UPnP::DEBUG++;

	    foreach my $srv ($dev->getservicebyname(SONOS_SRV_AlarmClock), $dev->getservicebyname(SONOS_SRV_DeviceProperties), $dev->getservicebyname(SONOS_SRV_AVTransport)) {
		my $ss_res = $http_req->post($dev_addr, $dev_port, "SUBSCRIBE", $srv->geteventsuburl, {
		    NT => 'upnp:event',
		    Callback => sprintf('<%s/ev/%s>', $args{ss}, $zpid),
		    qq(User-Agent) => "$^O UPnP/1.1 sonos-cli/$VERSION",
		    Timeout => 'Second-'.($args{mx} + $args{iv}),
					     }, "");
	
		if ($Net::UPnP::DEBUG) {
		    print $ss_res->getstatus() . "\n";
		    print $ss_res->getheader() . "\n";
		    print $ss_res->getcontent() . "\n";
		}

		$Net::UPnP::DEBUG = undef;
	    }
	}

	my $zp = Net::UPnP::SONOS::ZonePlayer->new($self, $dev);
	
	if ($Net::UPnP::DEBUG) {
	    print "ssdp = $ssdp_res_msg\n";
	    print "description = $post_content\n";
	}

	$self->{_sonos}->{search}->{zps}->{$zpid} = $dev;
    });
    $self->{_sonos}->{search}->{timer} = AnyEvent->timer(after => ($args{mx} + 1), cb => sub {
	# drop watchers
	$self->{_sonos}->{search}->{io} = undef;
	$self->{_sonos}->{search}->{timer} = undef;


	$self->{_sonos}->{zones} = undef;
	$self->{_sonos}->{groups} = undef;

	foreach my $zp (()) { #@{$self->{_sonos}->{search}->{zps}}) {
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

	    if($self->{_sonos}->{zones}->{$UDN}->{PositionInfo}->{TrackURI} =~ /^x-rincon:(RINCON_[\dA-F]+)/) {
		push(@{$self->{_sonos}->{groups}->{$1}}, $UDN);
	    }
	    else {
		push(@{$self->{_sonos}->{groups}->{$UDN}}, $UDN);
	    }
	}


	&{$args{cb}}($self) if(defined($args{cb}));
    });
}


sub getZones {
    my $self = shift;
    $self->search() unless(exists($self->{_sonos}->{zones}) && defined($self->{_sonos}->{zones}));
    
    return ( ) unless(exists($self->{_sonos}->{zones}) && defined($self->{_sonos}->{zones}));

    return %{$self->{_sonos}->{zones}};
}

sub getGroups {
    my $self = shift;
    $self->search() unless(exists($self->{_sonos}->{groups}) && defined($self->{_sonos}->{groups}));

    return ( ) unless(exists($self->{_sonos}->{groups}) && defined($self->{_sonos}->{groups}));

    return %{$self->{_sonos}->{groups}};
}

1;
