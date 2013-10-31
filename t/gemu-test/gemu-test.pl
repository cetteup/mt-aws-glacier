#!/usr/bin/env perl

use strict;
use warnings;
use v5.10;
use utf8;
use lib '../../lib';
use Data::Dumper;
use Carp;
use File::Basename;
use Encode;
use File::Path qw/mkpath rmtree/;
use Getopt::Long;
use App::MtAws::TreeHash;
use List::Util qw/first/;


our %task_seen;
our @priority = qw/command subcommand/;
our $data;
our %priority;
{
	my $i;
	map { $priority{$_} = ++$i } @priority;
}
our %filter;

our $FILTER='';
GetOptions ("filter=s" => \$FILTER );

map {
	if (my ($k, $vals) = /^([^=]+)=(.*)$/) {
		my @vals = split ',', $vals;
		$filter{$k} = { map { $_ => 1 } @vals };
	} else {
		confess $FILTER, $_;
	}
} split (' ', $FILTER);

binmode STDOUT, ":encoding(UTF-8)";

sub bool($)
{
	$_[0] ? 1 : 0
}

sub lfor(@)
{
	my ($cb, $key, @values) = (pop, @_);
	for (@values) {
		if (my ($mainkey) = $key =~ /\A\-(.*)$/) {
			confess if defined $data->{$mainkey};
		} else {
			confess if defined $data->{"-$key"};
		}
		local $data->{$key} = $_;
		$cb->();
	}
}

sub get($) {
	my $key = shift;
	confess unless $key;
	confess if $key =~ /\A\-/;
	confess if defined $data->{$key} && defined $data->{"-$key"};
	my $v;
	if (defined ($v = $data->{$key})) {
		$v;
	} elsif (defined ($v = $data->{"-$key"})) {
		$v;
	} else {
		confess Dumper [$key, $data];
	}
};



sub AUTOLOAD
{
	use vars qw/$AUTOLOAD/;
	$AUTOLOAD =~ s/^.*:://;
	get("$AUTOLOAD");
};



sub process
{
	for my $k1 (keys %filter) {
		return unless defined $data->{$k1};
		return unless first { $data->{$k1} eq $_ } keys %{ $filter{$k1} };
	}

	my $task = ( join(" ",
		map {
			my $v = $data->{$_};
			$_ =~ s/^\-//; "$_=$v"
		} sort {
			( ($priority{$a}||100_000) <=> ($priority{$b}||100_000) ) || ($a cmp $b);
		} grep {
			!/\A\-/
		} keys %$data
	));

	return  if $task_seen{$task};
	$task_seen{$task}=1;
	print $task, "\n";
}

sub gen_filename
{
	my ($cb, @types) = (pop, @_);
	lfor -filename_type => @types, sub {
		lfor filename => do {
			if (filename_type() eq 'zero') {
				"0"
			} elsif (filename_type() eq 'default') {
				"somefile"
			} elsif (filename_type() eq 'russian') {
				"файл"
			} else {
				confess;
			}
		}, $cb;
	}
}

sub gen_filesize
{
	my ($cb, $type) = (pop, shift);
	lfor -filesize_type => $type, sub {
		lfor filesize => do {
			if (filesize_type() eq '1') {
				1
			} elsif (filesize_type() eq '4') {
				1, 1024*1024-1, 4*1024*1024+1
			} elsif (filesize_type() eq 'big') {
				1, 1024*1024-1, 4*1024*1024+1, 45*1024*1024-156897
			} else {
				confess
			}

		}, $cb;
	}
}

sub roll_partsize
{
	my $partsize = shift;
	if ($partsize eq '1') {
		1
	} elsif ($partsize eq '2') {
		1, 2
	} elsif ($partsize eq '4') {
		1, 2, 4
	} else {
		confess $partsize;
	}
}

sub roll_concurrency
{
	my $concurrency = shift;
	if ($concurrency eq '1') {
		1
	} elsif ($concurrency eq '2') {
		1, 2
	} elsif ($concurrency eq '4') {
		1, 2, 4
	} elsif ($concurrency eq '20') {
		1, 2, 4, 20
	} else {
		confess $concurrency;
	}
}

sub file_sizes
{
	my ($cb, $filesize, $partsize, $concurrency) = (pop, @_);
	gen_filesize $filesize, sub {
		lfor partsize =>roll_partsize($partsize), sub {
			lfor concurrency =>roll_concurrency($concurrency), sub {
				my $r = get("filesize") / (get("partsize")*1024*1024);
				if ($r < 3 && get "concurrency" > 2) {
					# nothing
				} else {
					$cb->();
				}
			}
		}
	}
}


sub roll_russian_encodings
{
	my ($encodings_type) = @_;
	if ($encodings_type eq 'none') {
		"UTF-8"
	} elsif ($encodings_type eq 'simple') {
		qw/UTF-8 KOI8-R/;
	} elsif ($encodings_type eq 'full') {
		qw/UTF-8 KOI8-R CP1251/;
	} else {
		confess $encodings_type;
	}
}

sub file_names
{
	my ($cb, $filenames_types, $filename_encodings_type, $terminal_encodings_type) = (pop, @_);
	gen_filename @$filenames_types,  sub {
		lfor -russian_text => bool(filename_type() eq 'russian'), sub {
			lfor -terminal_encoding_type => qw/utf singlebyte/, sub {
				if (get "russian_text" || get "terminal_encoding_type" eq 'utf') {
					lfor filenames_encoding => do {
						if (get "russian_text" && get "terminal_encoding_type" eq 'singlebyte') {
							roll_russian_encodings($filename_encodings_type);
						} else {
							"UTF-8"
						}
					}, sub {
					lfor terminal_encoding => do {
						if (get "russian_text" && get "terminal_encoding_type" eq 'singlebyte') {
							roll_russian_encodings($terminal_encodings_type);
						} else {
							"UTF-8"
						}
					}, $cb
					}
				}
			}
		}
	}
}

sub file_body
{
	my ($cb, @types) = (pop, @_);
	lfor filebody => @types, sub {
		if (filesize() == 1 || filebody() eq 'normal') {
			if (filename_type() eq 'default' || filebody() eq 'normal') {
				$cb->();
			}
		}
	}
}

sub other_files
{
	my $cb = shift;
	$cb->();
	lfor otherfiles => 1, sub {
	lfor otherfiles_count => qw/0 1 10 100/, sub {
		if (otherfiles_count() < 20 || filesize() > 10) {
			lfor otherfiles_size => 1, 1024*1024-1, 4*1024*1024+1, sub {
				lfor otherfiles_big_count => qw/0 1/, sub {
					if (otherfiles_big_count() > 0) {
						lfor otherfiles_big_size =>  4*1024*1024+1, 45*1024*1024-156897, sub {
							if (otherfiles_big_size() > otherfiles_size()) {
								if (otherfiles_big_size() < 40*1024*1024 || filesize() > 3*1024*1024) {
									$cb->();
								}
							}
						}
					} elsif (otherfiles_count() > 0) {
						$cb->();
					}
				}
			}
		}
	}
	}
}

sub heavy_filenames
{
	my ($cb) = @_;
	file_sizes 4, 2, 4, sub {
	file_names [qw/zero russian/], 'full', 'full', sub {
	file_body qw/normal/, sub {
		$cb->();
	}}};
}

sub heavy_other_files
{
	my ($cb) = @_;
	file_sizes 'big', 4, 20, sub {
	file_names [qw/default/], 'simple', 'none', sub {
	file_body qw/normal/, sub {
	other_files sub {
		$cb->();
	}}}};
}

sub light_other_files
{
	my ($cb) = @_;
	file_sizes 1, 4, 20, sub {
	file_names [qw/default/], 'simple', 'none', sub {
	file_body qw/normal/, sub {
	lfor otherfiles => 1, sub {
	lfor otherfiles_count => qw/0 1 10/, sub {
		if (otherfiles_count() < 20 || filesize() > 10) {
			lfor otherfiles_size => 1, 1024*1024-1, 4*1024*1024+1, sub {
				lfor otherfiles_big_count => qw/0 1/, sub {
					if (otherfiles_big_count() > 0) {
						lfor otherfiles_big_size =>  4*1024*1024+1, sub {
							if (otherfiles_big_size() > otherfiles_size()) {
								if (otherfiles_big_size() < 40*1024*1024 || filesize() > 3*1024*1024) {
									$cb->();
								}
							}
						}
					} elsif (otherfiles_count() > 0) {
						$cb->();
					}
				}
			}
		}
	}
	}
	}}};
}

sub heavy_fsm
{
	my ($cb) = @_;
	file_sizes 'big', 4, 20, sub {
	file_names [qw/default zero russian/], 'simple', 'none', sub {
	file_body qw/normal zero/, sub {
		$cb->();
	}}};
	heavy_other_files(sub {
		$cb->();
	});
}

lfor command => qw/sync/, sub {
	if (command() eq "sync") {
		lfor subcommand => qw/sync_new sync_modified sync_missing/, sub {
			if (get "subcommand" eq "sync_new") {
				# testing filename stuff
				heavy_filenames sub {
					process();
				};
				# testing FSM stuff
				heavy_fsm sub {
					process();
				};
			} elsif (get "subcommand" eq "sync_missing") {
				# testing filename stuff
				lfor is_missing => 0, 1, sub {
				file_sizes 1, 1, 1, sub {
				file_names [qw/zero russian/], 'full', 'full', sub {
				file_body qw/normal/, sub {
					process();
				}}};
				};
				lfor is_missing => 1, sub {
				light_other_files(sub {
					process();
				});
				}
			} elsif (get "subcommand" eq "sync_modified") {

				my @detect_cases = qw/
					treehash-matches
					treehash-nomatch
					mtime-matches
					mtime-nomatch
					mtime-and-treehash-matches-treehashfail
					mtime-and-treehash-matches-treehashok
					mtime-and-treehash-nomatch
					mtime-or-treehash-matches
					mtime-or-treehash-nomatch-treehashok
					mtime-or-treehash-nomatch-treehashfail
					always-positive
					size-only-matches
					size-only-nomatch
				/;

				lfor detect_case => @detect_cases, sub { # TODO: also try mtime=zero!
				# testing filename stuff
				file_sizes 1, 1, 1, sub {
				file_names [qw/zero russian/], 'simple', 'none', sub {
				file_body qw/normal/, sub {
					process();
				}}}};

				lfor detect_case => qw/treehash-matches mtime-matches/, sub { # TODO: also try mtime=zero!
					heavy_fsm sub {
						process();
					};
				};

			}
		}
	}
};





__END__
