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


# Please be aware: most of the code accessing Google's Translate API is based on
# the package Speech::Google::TTS 0.74:
#
#   Module that uses Google Translate for text to speech synthesis.
#
#   Copyright (C) 2013, by Niels Dettenbach <nd@syndicat.com> 
#   with contributes of Lefteris Zafiris <zaf.000@gmail.com>
#
#   This program is free software, distributed under the terms of
#   the GNU General Public License Version 2.
#

package Net::UPnP::SONOS::Speak;

use Speech::Google::TTS;
use Digest;
use File::Basename;
use File::Path qw(make_path);
use Fcntl;
use NDBM_File;
use Log::Any;
use File::Temp qw(tempfile tempdir);
use CGI::Util qw(escape);
use LWP::UserAgent;
use LWP::ConnCache;

use strict;
use warnings;

sub new($) {
    my $class = shift;
    my $self = {};
    bless $self, $class;

    $self->{lang} = 'de';
    $self->{cachedir} = "/srv/heap/readout";
    $self->{timeout} = '10';
    $self->{googleurl} = qq(http://translate.google.com/translate_tts);

    $self->{ua} = LWP::UserAgent->new;
    $self->{ua}->agent("Mozilla/5.0 (X11; Linux; rv:8.0) Gecko/20100101");
    $self->{ua}->env_proxy;
    $self->{ua}->conn_cache(LWP::ConnCache->new());
    $self->{ua}->timeout($self->{timeout});
    
    $self->{_sonos}->{logger} = Log::Any->get_logger(category => __PACKAGE__);

    $self->{langdir} = "$self->{cachedir}/$self->{lang}";
    unless(-d $self->{langdir}) {
	my $err;
	make_path($self->{langdir}, {error => \$err});
	die "Could not create directory ".join('; ', mperr($err))."\n" if(@$err);
    }

    my %cache;
    tie(%cache, 'NDBM_File', "$self->{cachedir}/content-$self->{lang}", O_RDWR|O_CREAT, 0666);
    $self->{cache} = \%cache;

    $self->{digest} = Digest->new(qq(MD5));
    $self->{m3u} = { };

    return $self;
}

sub mperr($) {
    my $err = shift;
    my @err;

    return unless(@$err);

    for my $diag (@$err) {
	my ($f, $m) = %$diag;
	push(@err, ($f ? "$f: " : '').$m);
    }

    return @err;
}

sub cachedir {
    my $self = shift;

    return $self->{langdir};
}

sub open {
    my $self = shift;
    my $dig = shift;

    unless(exists(($self->{m3u}->{$dig}))) {
	$self->{_sonos}->{logger}->notice("unknown digest '$dig'");
	return undef;
    }

    my @files = @{ $self->{m3u}->{$dig} };

    if($#files == 0) {
	my $fh;

	unless(open($fh, '<', "$self->{langdir}/$files[0]")) {
	    $self->{_sonos}->{logger}->notice("failed to open cached file '$files[0]': $!");
	    return undef;
	}
	return $fh;
    }
    else {
	my $fh;

	unless(open($fh, '-|', 'cat', map { "$self->{langdir}/$_" } @files)) {
	    $self->{_sonos}->{logger}->notice("failed to fork cat: $!");
	    return undef;
	}
	return $fh;
    }

    return undef;
}

sub say {
    my $self = shift;
    my @text = map {
	s/[\\|*~<>^\n\(\)\[\]\{\}[:cntrl:]]/ /g;
	s/\s+/ /g;
	s/^\s|\s$//g;

	lc;
    } @_;

    $self->{digest}->reset;
    $self->{digest}->add(join("\n", @text));
    my $dig = $self->{digest}->hexdigest;

    return $dig if(exists($self->{m3u}->{$dig}));

    my @mp3list;
    for (@text) {
	# Split input text to comply with google tts requirements #
	return if (!length);

	$_ .= '.' unless (/^.+[.,?!:;]$/);
	@text = /.{1,100}[.,?!:;]|.{1,100}\s/g;

	foreach my $line (@text) {
	    # Get speech data from google and save them in temp files #
	    $line =~ s/^\s+|\s+$//g;
	    next if (length($line) == 0);

	    if($self->{cache}->{$line}) {
		push(@mp3list, $self->{cache}->{$line});
	    }
	    else {
		$line = escape($line);
	    
		my ($mp3_fh, $mp3_name) = tempfile(
		    "tts_XXXXXX",
		    DIR    => $self->{langdir},
		    SUFFIX => ".mp3",
		    UNLINK => 0
		    );

		my $request = HTTP::Request->new(GET => "$self->{googleurl}?tl=$self->{lang}&q=$line");
		my $response = $self->{ua}->request($request, $mp3_name);
		if (!$response->is_success) {
		    $self->{_sonos}->{logger}->warn("Failed to fetch speech data.");
		} else {
		    my $fn = basename($mp3_name);
		    $self->{cache}->{$line} = $fn;
		    push(@mp3list, $fn);
		}
	    }
	}
    }

    $self->{m3u}->{$dig} = \@mp3list;
    return $dig;
}

1;
