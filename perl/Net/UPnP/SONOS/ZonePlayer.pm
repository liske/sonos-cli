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

our $VERSION = '0.1.0';

sub new {
    my ($class, $cp, $zp) = @_;
    my $self = { };


    $self->{_zp_cp} = $cp;
    $self->{_zp_dev} = $zp;

    my $cb = sub {
	my ($service, %properties) = @_;

	print("Event received for service " . $service->serviceId . "\n");
	while (my ($key, $val) = each %properties) {
	    print("\tProperty ${key}'s value is " . $val . "\n");
	}
    };

    $self->{_zp_services}->{(SONOS_SRV_AlarmClock)} = $zp->getservicebyname(SONOS_SRV_AlarmClock);
    $self->{_zp_services}->{(SONOS_SRV_DeviceProperties)} = $zp->getservicebyname(SONOS_SRV_DeviceProperties);
    $self->{_zp_services}->{(SONOS_SRV_AVTransport)} = $zp->getservicebyname(SONOS_SRV_AVTransport);

    bless $self, $class;
    return $self;
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
