# sonos-cli - Command line interface to control 'Sonos ZonePlayer' 
#
# Authors:
#   Thomas Liske <thomas@fiasko-nw.net>
#
# Copyright Holder:
#   2010 - 2014 (C) Thomas Liske [http://fiasko-nw.net/~thomas/]
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

package Net::UPnP::SONOS::Config;

use Log::Any;

use strict;
use warnings;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(sonos_config_get sonos_config_register);

my %config;
my %syntax;
my $_logger = Log::Any->get_logger(category => __PACKAGE__);

sub sonos_config_get {
    my $opt = shift;

    unless(exists($syntax{$opt})) {
	my @c = caller;
	$_logger->warn("package $c[0] ($c[1]:$c[2]) requests unknown option '$opt'");
	return undef;
    }

    return undef unless(exists($config{$opt}));

    return $config{$opt};
}

sub sonos_config_load($) {
    my $fn = shift || '/etc/sonos-cli.conf';

    die "could not read config file '$fn'\n" unless(-r $fn);

    eval `cat "$fn"`;
    die "$@\n" if($@);

    my %rqo = map { $syntax{$_}->{required}; } keys %syntax;
    foreach my $opt (keys %config) {
	unless(exists($syntax{$opt})) {
	    $_logger->warn("ignoring unknown option '$opt'");
	    continue;
	}

	delete($rqo{$opt});

	die "invalid option '$opt' - does not match $syntax{$opt}->{re}\n"
	    unless($syntax{$opt}->{re} =~ $config{$opt});
    }

    die("required options not configured: ".join(', ', keys %rqo)."\n") if(scalar keys %rqo);
}

sub sonos_config_register($$@) {
    my $opt = shift;
    my $regex = shift;
    my $required = shift || 0;
    my $default = shift;

    $syntax{$opt} = {
	regex => $regex,
	required => $required,
    };
    $config{$opt} = $default;

    $_logger->warn("register option $opt");
}

1;
