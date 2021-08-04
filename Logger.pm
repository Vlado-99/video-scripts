#!/usr/bin/perl
use strict;
use warnings;

package Logger;
require Exporter;
use namespace::autoclean;
use DateTime;

sub LOGstart;
sub LOG;
sub LOGcat;

our @ISA = qw(Exporter);
our @EXPORT = qw( LOGstart LOG LOGcat LOGnDie GlobalLogger );  # symbols to export

=pod

=encoding utf8

=head1 Logger

=head2 Synopsis

    my $logger = Logger->new( 'logfile', separator => '+', encoding => 'Windows-1250', prefix => 'modulename', stderr => 1);
        # defaults:
        #   separator = ' '
        #   encoding    none
        #   prefix    = ''
        #   stderr    = 0 (false = do not duplicate output to STDERR)
    $logger->log( 'string1', 'string2', ...);
        # YYYYmmdd-HHMMSS:modulename: string1+string2 ....
    my @lines = ( 'line 1', 'line 2');
    $logger->logcat( \@lines);
        # YYYYmmdd-HHMMSS:modulename: line 1
        # YYYYmmdd-HHMMSS:modulename: line 2
    $logger->logcat( @lines);
        # YYYYmmdd-HHMMSS:modulename: line 1
        # YYYYmmdd-HHMMSS:modulename: line 2
    $logger->logcat( 'filename', { encoding => 'input encoding'});

=cut

sub new
{
    my $class = shift;
    my ($logfile,%param) = @_;

    my $self = { # defaults:
        separator => ' ', encoding => undef, prefix => '', stderr => 0,
    };
    foreach (keys %param) {
        if( exists $self->{$_} ) {
            $self->{$_} = $param{$_};
        }else {
            die( "Unknown parameter '$_'.\n");
        }
    }
    $self->{logfile} = $logfile;
    my $open_opt = '';
    $open_opt .= ':encoding('.$self->{encoding}.')' if defined $self->{encoding};
    open my $loghandle, '>>'.$open_opt, $self->{logfile}
        or die( "Cannot open '$logfile': $!\n");
    $self->{fh} = $loghandle;
    return bless $self, $class;
}

sub DESTROY
{
    my $self = shift;
    close( $self->{fh});
}

sub log
{
    my $self = shift;
    my $now = DateTime->now( time_zone => 'Europe/Bratislava');
    my $nowstr = sprintf( "%04d%02d%02d-%02d%02d%02d",
        $now->year,$now->month,$now->day,$now->hour,$now->minute,$now->second);
    print {$self->{fh}} ($nowstr, ':',$self->{prefix},': ', join( $self->{separator}, @_), "\n");
    if( $self->{stderr} ) {
        print STDERR ( join( $self->{separator}, @_), "\n");
    }
}

sub logcat
{
    my $self = shift;
    if( scalar @_ == 1 && ref $_[0] eq 'ARRAY' ) {
        foreach (@{$_[0]}) {
            $self->log( $_);
        }
    }elsif( scalar @_ == 2 && ref $_[1] eq 'HASH' ) {
        my $encoding = '';
        $encoding = ":encoding($_[1]->{encoding})" if defined $_[1]->{encoding};
        if( open my $h, '<'.$encoding, $_[0] ) {
            while( <$h> ) {
                chomp;
                $self->log( $_);
            }
            close( $h);
        }else {
            $self->log( "logcat: Cannot open file '".$_[0]."'");
        }
    }else { # log each on separate line
        $self->log( $_) foreach (@_);
    }
}

sub separator
{
	my ($self,$new_separator) = @_;
	$self->{separator} = $new_separator if defined $new_separator;
	return $self->{separator};
}

#===== Functions

my $global_logger;

sub GlobalLogger
{
    return $global_logger;
}

sub LOGstart
{
    die( "LOGstart: global_logger already started!\n")
        if defined $global_logger;
    $global_logger = Logger->new( @_);
}

sub LOG
{
    die( "LOG: global logger not started!\n")
        unless defined $global_logger;
    $global_logger->log( @_);
}

sub LOGcat
{
    die( "LOGcat: global logger not started!\n")
        unless defined $global_logger;
    $global_logger->logcat( @_);
}

sub LOGnDie
{
    die( "LOG: global logger not started!\n")
        unless defined $global_logger;
    $global_logger->{stderr} = 1;
    $global_logger->log( @_);
    exit(1);
}

END {
    $global_logger = undef;
}

1;
