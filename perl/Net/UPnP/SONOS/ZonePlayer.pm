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

package Net::UPnP::SONOS::ZonePlayer;

use Net::UPnP::SONOS;

use constant {
    SONOS_STATUS_OK => 200,

    SONOS_SRV_AlarmClock => 'urn:schemas-upnp-org:service:AlarmClock:1',
    SONOS_SRV_DeviceProperties => 'urn:schemas-upnp-org:service:DeviceProperties:1',
    SONOS_SRV_AVTransport => 'urn:schemas-upnp-org:service:AVTransport:1',
};

use strict;
use warnings;
use Carp;

use Net::UPnP::Device;
require Exporter;
our @ISA = qw(Net::UPnP::Device Exporter);

sub new {
    my ($class, $httpd) = @_;
    my $self = $class->SUPER::new();

    $self->{_sonos}->{httpd} = $httpd;
    $self->{_sonos}->{search_timeout} = 3;

    bless $self, $class;
    return $self;
}


sub getDevIP {
    my $self = shift;

    my $loc = $self->getlocation();
    $loc =~ /http:\/\/([0-9a-z.]+)[:]*([0-9]*)\//i;

    return ($1, $2 || 1400);
}

sub getLocalIP {
    my $self = shift;

    return $self->{_zp_localip} if (exists($self->{_zp_localip}));

    my $ip = '8.8.8.8';

    my $loc = $self->getlocation();
    $ip = $1 if($loc =~ /http:\/\/([0-9a-z.]+)[:]*([0-9]*)\//i);

    use IO::Socket::INET;
    my $sock = IO::Socket::INET->new(
        Proto    => 'udp',
        PeerAddr => $ip,
        PeerPort => '53',
    );

    $self->{_zp_localip} = $sock->sockhost;

    close($sock);

    return $self->{_zp_localip};
}

sub getUDN($) {
    my $self = shift;

    return "uuid:$1" if ($self->getdescription =~ /(RINCON_[\dA-F]+)/);

    return undef;
}

sub UDN2ShortID($) {
    my $UDN = shift;

    $UDN =~ s/^uuid:RINCON_//;
    $UDN =~ s/01400$//;

    return $UDN;
}

sub getShortID($) {
    my $self = shift;

    return UDN2ShortID( $self->getUDN() );
}

sub subEvents($$) {
    my $self = shift;

    my $lsip = $self->{_sonos}->{httpd}->host;
    $lsip = $self->getLocalIP() if($lsip eq '0.0.0.0');
    
    my $devid = $self->getShortID();
    my $req = Net::UPnP::HTTP->new();
    foreach my $srv ($self->getservicelist()) {
	$Net::UPnP::DEBUG++;
	
	my $srvid = $srv->geteventsuburl;
	my %params = (
	    qq(User-Agent) => "$^O UPnP/1.1 sonos-cli/$Net::UPnP::SONOS::VERSION",
	    TIMEOUT => 'Second-900',
	    );
	if(exists($self->{_zp_sub}->{sid}->{$srvid})) {
	    $params{SID} = $self->{_zp_sub}->{sid}->{$srvid};
	}
	else {
	    $params{NT} = 'upnp:event';
	    $params{Callback} = sprintf('<http://%s:%d/%s>', $lsip, $self->{_sonos}->{httpd}->port, $devid);
	}
	
	my $res = $req->post($self->getDevIP(), "SUBSCRIBE", $srv->geteventsuburl, \%params, "");
    $Net::UPnP::DEBUG--;

	if($res->getstatuscode() == 200) {
	    my $h = $res->getheader();
	    
	    # get parameters to refresh the subscription
	    my $renew = 900;
	    $h =~ /SID:\s+(.+)/; 
	    $self->{_zp_sub}->{sid}->{$srvid} = $1;
	    $renew = $1 if($h =~ /TIMEOUT:\s+Second-(.+)/);
	    
	    # refresh before timeout
	    $renew *= 0.5;
	    $self->{_zp_sub}->{w} = AnyEvent->timer(
		after => $renew,
		cb => sub {
		    $self->subEvents($self->{_sonos}->{httpd});
		},);
	}
	else {
	    $self->{_zp_sub}->{w} = AnyEvent->timer(
		after => 900,
		cb => sub {
		    $self->subEvents($self->{_sonos}->{httpd});
		},);
	}
    }
}

sub avtPlay(;$) {
    my $self = shift;

    die "N/A";
}


sub avtPause() {
    my $self = shift;

    die "N/A";
}


sub avtStop() {
    my $self = shift;

    die "N/A";
}


sub avtToggle() {
    my $self = shift;

    die "N/A";
}


sub avtNext() {
    my $self = shift;

    die "N/A";
}

sub avtPrevious() {
    my $self = shift;

    die "N/A";
}


sub dpLED() {
    my $self = shift;
}

1;
