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

package Net::UPnP::ControlPoint::SONOS;

use strict;
use warnings;

use Net::UPnP::ControlPoint;
our @ISA = qw(Net::UPnP::ControlPoint);

use constant {
    STATUS_OK => 200,

    SRV_DeviceProperties => 'urn:schemas-upnp-org:service:DeviceProperties:1',
    SRV_AVTransport => 'urn:schemas-upnp-org:service:AVTransport:1',
};

sub new {
    my ($class) = @_;
    my $self = $class->SUPER::new();

    $self->{_sonos}->{search_timeout} = 5;

    bless $self, $class;
    return $self;
}

sub search {
    my $self = shift;
    $self->{_sonos}->{devices} = undef;
    $self->{_sonos}->{zones} = undef;

    my @devs = $self->SUPER::search(st => 'urn:schemas-upnp-org:device:ZonePlayer:1', mx => $self->{_sonos}->{search_timeout});
    foreach my $dev (@devs) {
	my %services;
	$services{(SRV_DeviceProperties)} = $dev->getservicebyname(SRV_DeviceProperties);
	$services{(SRV_AVTransport)} = $dev->getservicebyname(SRV_AVTransport);


	# GetZoneInfo (get MACAddress to build UDN)
	# HACK: $dev->getudn() is broken, try to build the UDN
	#       from the MACAddress - this might fail :-(
	my $aresp = $services{(SRV_DeviceProperties)}->postaction('GetZoneInfo');
	if($aresp->getstatuscode != STATUS_OK) {
	    print STDERR "Got error code ".$aresp->getstatuscode."!\n";
	    next;
	}
	my $ZoneInfo = $aresp->getargumentlist;
	my $UDN = $ZoneInfo->{MACAddress};
	$UDN =~ s/://g;
	$UDN = "RINCON_${UDN}01400";

	$self->{_sonos}->{devices}->{$UDN}->{dev} = $dev;
	$self->{_sonos}->{devices}->{$UDN}->{services} = \%services;
	$self->{_sonos}->{devices}->{$UDN}->{ZoneInfo} = $ZoneInfo;


	# GetZoneAttributes (get zone name)
	$aresp = $services{(SRV_DeviceProperties)}->postaction('GetZoneAttributes');
	if($aresp->getstatuscode != STATUS_OK) {
	    print STDERR "Got error code ".$aresp->getstatuscode."!\n";
	    next;
	}
	$self->{_sonos}->{devices}->{$UDN}->{ZoneAttributes} = $aresp->getargumentlist;


	my %aargs = (
	    'InstanceID' => 0,
	);


	$aresp = $services{(SRV_AVTransport)}->postaction('GetPositionInfo', \%aargs);
	if($aresp->getstatuscode != STATUS_OK) {
	    print STDERR "Got error code ".$aresp->getstatuscode."!\n";
	    next;
	}
	$self->{_sonos}->{devices}->{$UDN}->{PositionInfo} = $aresp->getargumentlist;


	$aresp = $services{(SRV_AVTransport)}->postaction('GetTransportInfo', \%aargs);
	if($aresp->getstatuscode != STATUS_OK) {
	    print STDERR "Got error code ".$aresp->getstatuscode."!\n";
	    next;
	}
	$self->{_sonos}->{devices}->{$UDN}->{TransportInfo} = $aresp->getargumentlist;

	if($self->{_sonos}->{devices}->{$UDN}->{PositionInfo}->{TrackURI} =~ /^x-rincon:(RINCON_[\dA-F]+)/) {
	    push(@{$self->{_sonos}->{zones}->{$1}}, $UDN);
	}
	else {
	    push(@{$self->{_sonos}->{zones}->{$UDN}}, $UDN);
	}
    }
}

sub getDevices {
    my $self = shift;
    $self->search() unless(exists($self->{_sonos}->{devices}) && defined($self->{_sonos}->{devices}));

    return %{$self->{_sonos}->{devices}};
}

sub getZones {
    my $self = shift;
    $self->search() unless(exists($self->{_sonos}->{zones}) && defined($self->{_sonos}->{zones}));

    return %{$self->{_sonos}->{zones}};
}

1;
