@SETLOCAL ENABLEEXTENSIONS
@C:\Strawberry\perl\bin\perl.exe -x "%~f0" %*
@exit /b %ERRORLEVEL%
#!perl
#line 6
# Určené pre Strawberry Perl, vstup a výstup cez CMD konzolu.
use 5.28.1;
use strict;
use warnings;
use Encode;
use utf8;
use Term::ReadKey;
use File::Copy qw(move);
use FindBin qw($RealBin $Script);
use lib $RealBin;
use Logger;
use Win32;
use Win32::Process;

# TODO: set correct metadata for audio stream: -metadata:s:a:0 language=dut -metadata:s:a:0 title="NL"
# TODO: set -disposition default for audio and subtitle streams (like -disposition:a:0 default -disposition:a:1 0)
# TODO: embed external subtitle file into mkv

binmode STDIN, ":encoding(CP-852)";
binmode STDOUT, ":encoding(CP-852)";
binmode STDERR, ":encoding(CP-852)";
select STDERR; $|=1;
select STDOUT; $|=1;

my $fn_separator = '\\';
my $ffpath   = "C:\\mediatools\\ffmpeg\\bin";
my $ffmpeg   = fnmerge( "$ffpath", "ffmpeg.exe");
my $ffprobe  = fnmerge( "$ffpath", "ffprobe.exe");
my $ffplay   = fnmerge( "$ffpath", "ffplay.exe");
my $jobpath  = "C:\\mediatools\\ffmpeg.jobs";

our $Signal = 0;
$SIG{INT} = sub {
  warn "Caught SIGINT; please stand by, I'm leaving as soon as possible...\n";
  $Signal++;
};

if( scalar @ARGV > 0 ) {
	if( $ARGV[0] eq '--go' ) {
		daemon_mode();
		exit 0;
	}elsif( $ARGV[0] eq '--play' ) {
		shift @ARGV;
		player_mode();
		exit 0;
	}else {
		interactive_mode();
		exit 0;
	}
}
usage();

##############################################################################

sub usage
{
	print <<"USAGE";
FFMASTER.pl - ffmpeg preprocessor
Usage:
FFMASTER.pl fileA [fileB ...]
	- run in interactive mode to create new conversion job
FFMASTER.pl --go
	- run in daemon (batch job processing) mode
FFMASTER.pl --play fileA [fileB ...]
	- run as ffplay
Paths:
	ffmpeg  = $ffmpeg
	jobpath = $jobpath
More info in POD or attached FFMASTER.html.
USAGE

	pause();
	exit 1;
}

sub encode_win
{
	return encode( 'Windows-1250', $_[0]);
}

sub decode_win
{
	return decode( 'Windows-1250', $_[0]);
}

sub return_exec_error
{
	return undef if $?==0;
	return "ERROR: Failed to execute: $!" if $? == -1;
	return (sprintf "ERROR: Child died with signal %d, %s coredump",
			($? & 127),  ($? & 128) ? 'with' : 'without')
		if $? & 127;
	return sprintf( "Child exited with value %d", $? >> 8);
}

sub die_if_exec_error
{
	my $msg = $_[0] // return_exec_error();
	return unless defined $msg;
	die( "\n$msg\n") if $msg=~m/^ERROR:/;
	print STDERR "\n$msg\n";
}

sub fnsplit
{
	my ($file) = @_;
	my $fnsr = $fn_separator =~ s/\\/\\\\/gr;
	if( $file =~ m/^(.*)$fnsr([^$fnsr]+)$/ ) {
		my ($d,$n) = ($1,$2);
		$d .= $fn_separator if $d eq '' || $d =~ m/\w:$/;
		return ($d,$n);
	}elsif( $file =~ m/^(.*)$fnsr$/ ) {
		my ($d,$n) = ($1,'');
		$d .= $fn_separator if $d eq '' || $d =~ m/\w:$/;
		return ($d,$n);
	}elsif( $file =~ m/^(\w:)(.*)$/ ) {
		return ($1,$2);
	}else {
		return ('',$file);
	}
}

sub fnmerge
{
	my ($merged,@parts) = grep {defined($_)} @_;
	return undef unless defined $merged;
	$merged = shift @parts while $merged eq '' && scalar(@parts)>0;

	foreach (@parts) {
		if( substr($merged,-1) eq $fn_separator
			&& substr($_,0,1) eq $fn_separator ) {
			$merged .= substr($_,1);
		}elsif( substr($merged,-1) ne $fn_separator
			&& substr($_,0,1) ne $fn_separator
			&& substr($merged,-1) ne ':' ) {
			$merged .= $fn_separator . $_;
		}else {
			$merged .= $_;
		}
	}
	return $merged;
}

sub fn_tests
{ # test
	my @fnsplit_tests = (
		[ 'C:\\dir\\filename.txt', 'C:\\dir',   'filename.txt'],
		[ '\\dir\\filename.txt',   '\\dir',     'filename.txt'],
		[ '\\filename.txt',        '\\',        'filename.txt'],
		[ 'filename.txt',          '',          'filename.txt'],
		[ 'C:\\dir\\filename.',    'C:\\dir',   'filename.'],
		[ 'C:\\dir\\filename',     'C:\\dir',   'filename'],
		[ 'C:\\dir\\',             'C:\\dir',   ''],
		[ 'C:\\',                  'C:\\',      ''],
		[ 'C:',                    'C:',        ''],
		[ 'C:filename.txt',        'C:',        'filename.txt'],
	);
	foreach (@fnsplit_tests) {
		my ($f,$a,$b) = @$_;
		my ($ra,$rb) = fnsplit($f);
		die( "'$f' ==> ERROR ra='$ra', rb='$rb'\n") if $ra ne $a || $rb ne $b;
	}
	print "fnsplit: test OK.\n";
	foreach (@fnsplit_tests) {
		my ($f,$a,$b) = @$_;
		my ($m) = fnmerge($a,$b);
		die( "'$a' + '$b' ==> ERROR m='$m'\n") if $m ne $f;
	}
	print "fnmerge: test OK.\n";
	exit(0);
}
#fn_tests();

sub read_dir
{
	my ($name,%param) = @_;
	if( opendir my $dh, $name ) {
		my $ar = $param{to};
		$ar = [] unless defined $ar and ref $ar eq 'ARRAY';
		@$ar = grep {$_ !~ m/^\.\.?$/} map {chomp;$_} readdir $dh;
		closedir $dh;
		return $ar;
	}else {
		die "Cannot open $name: $!\n" unless defined($param{die}) && $param{die}==0;
		return undef;
	}
}

sub read_file
{
	my ($name,%param) = @_;
	if( open my $fh, '<:utf8', $name ) {
		my $ar = $param{to};
		$ar = [] unless defined $ar and ref $ar eq 'ARRAY';
		@$ar = map {chomp;$_} <$fh>;
		close $fh;
		return $ar;
	}else {
		die "Cannot open $name: $!\n" unless defined($param{die}) && $param{die}==0;
		return undef;
	}
}

sub write_file
{
	my ($name) = shift;
	my $param = +{};
	$param = shift if ref $_[0] eq 'HASH';
	my $lines = ref $_[0] eq 'ARRAY' ? $_[0] : \@_;
	if( open my $fh, '>:utf8', $name ) {
		print $fh join( "\n", @$lines);
		close $fh;
	}else {
		die "Cannot open $name: $!\n" unless defined($param->{die}) && $param->{die}==0;
		return undef;
	}
}

sub escape_re
{
	return $_[0] =~ s/([][().\\\$*+\@])/\\$1/gr;
}

sub pause
{
	print STDERR "Stlač kláves\n";
#	<STDIN>;
	ReadMode 'raw';
	while(1) {
		my $key = ReadKey -1;
		last if defined $key;
	}
	ReadMode 'restore';
}

sub read_answer
{
	my ($cases) = @_;
	my ($key,$keyre);
	ReadMode 'raw';
	while( !defined($key) || $cases !~ m/$keyre/ ) {
		exit 1 if $Signal;
		$key = ReadKey -1;
		next unless defined $key;
		$keyre = escape_re($key);
	}
	ReadMode 'restore';
	print "$key\n";
	return $key;
}

sub get_streams
{
	my ($file) = @_;
	$file = encode_win( $file);
	my @probe = 
		map {chomp; s/^\s+//; $_}
		qx| "$ffprobe" -hide_banner "$file" 2>&1 |;
	die_if_exec_error;
	my @streams =
		map {s/^Stream\s+//r}
		grep /^Stream\s+#/i, @probe;
	#print join("\n", @streams);
	my @video = grep /\sVideo:/i, @streams;
	my @audio = grep {m/\sAudio:/i && !m/visual impaired|descriptions/i} @streams;
	my @subtitle = grep {m/\sSubtitle:/i && !m/teletext|hearing impaired/i} @streams;

	my @duration = grep /Duration:\s+([0-9:.]+),\s+start:\s+([0-9.]+),/, @probe;
	my %param;
	if( defined($duration[0]) && $duration[0]=~m/Duration:\s+([0-9:.]+),\s+start:\s+([0-9.]+),/ ) {
		$param{duration} = $1;
		$param{start} = $2;
	}

	return (\@video,\@audio,\@subtitle,\%param);
}

sub get_all_names
{
	my @names;
	foreach my $file (@_) {
		my ($dir,$name) = fnsplit( $file);
		my ($begin,$num,$ext);
		if( $name =~ m/^(.*\D)(\d+)(\.[^.]+)$/ ) {
			($begin,$num,$ext) = ($1,$2,$3);
		}elsif( $name =~ m/^(\d+)(\.[^.]+)$/ ) {
			($begin,$num,$ext) = ('',$1,$2);
		}
		if( defined $begin ) {
			my $ndigits = length($num);
			$begin = escape_re($begin);
			$ext   = escape_re($ext);
			push @names, map {fnmerge($dir,$_)}
				grep {m/^$begin\d{$ndigits}$ext$/ && -f fnmerge($dir,$_)}
				@{read_dir($dir)};
		}else {
			push @names, $file;
		}
	}
	# keep names unique
	my %H = map{$_=>1} @names;
	@names = sort keys %H;
	#print join( "\n", @names);
	return map {decode_win($_)} @names;
}

sub print_choices
{
	my ($list,$prompt) = @_;
	$prompt = '' unless defined $prompt;
	my $i = 1;
	print join( "\n", map {sprintf("%2d - %s", $i++, $_)} @$list);
	print "\n$prompt";
}

sub read_choices
{
	my ($max) = @_;
	my $line = <STDIN>;
	exit 1 if $Signal;
	$line =~ s/^\s+|\s+$//g;
	return ( 1 .. $max ) if $line eq '*';
	return grep { 0<$_ && $_<=$max } ( $line=~/(\d)/g );
}

sub get_stream_id
{
	my ($name,$list,$i) = @_;
	if( $list->[$i] =~ m/#(\d+:\d+)/ ) {
		return $1;
	}else {
		die( "\n".__LINE__."\n$name '$list->[$i]'\n");
	}
}

sub create_job_file
{
	my ($path) = @_;
	my @used = sort grep /^job-\d{6}\./, @{read_dir($path)};
	my $max = 0;
	if( scalar @used > 0 ) {
		$max = $used[$#used]=~s/^job-0*(\d+)\D.*/$1/r;
	}
	for( my $n=$max+1; $n<=999999; $n++ ) {
		my $jobfile = fnmerge( $path, sprintf("job-%06d.temp",$n));
		next if -f $jobfile;
		return $jobfile if write_file( $jobfile, +{die=>0}, ' ');
	}
	die "Cannot create jobfile in '$path'!\n";
}

sub ErrorReport{
    print STDERR Win32::FormatMessage( Win32::GetLastError() );
}
 
sub seconds2hms
{
	my ($sec) = @_;
	my ($h,$m,$s);
	$h = int( $sec/60/60 );
	$sec -= $h*60*60;
	$m = int( $sec/60 );
	$sec -= $m*60;
	$s = int( $sec );
	$sec -= $s;
	return sprintf( "%d:%02d:%02d.%03d", $h, $m, $s, int($sec*1000));
}

sub change_job_state
{
	my ($jobfile,$curr,$new) = @_;
	my $newj = $jobfile=~s/$curr$/$new/r;
	return $newj if move $jobfile, $newj;
	return undef;
}

sub format_datetime
{
	my ($dt) = @_;
	return sprintf( "%d.%d.%d %d:%02d:%02d",
		$dt->day, $dt->month, $dt->year, $dt->hour, $dt->minute, $dt->second);
}

sub format_duration
{
	my ($diff_jd) = @_;
	my $sec = int($diff_jd*60*60*24);
	my $min  = int($sec/60);  $sec -= $min*60;
	my $hour = int($min/60);  $min -= $hour*60;
	my $day  = int($hour/24); $hour -= $day*24;
	if( $day>0 ) {
		return sprintf( "%dd %d:%02d:%02d", $day, $hour, $min, $sec);
	}else {
		return sprintf( "%d:%02d:%02d", $hour, $min, $sec);
	}
}

sub get_file_size
{
	return (stat(encode_win($_[0])))[7];
}

sub round2mb
{
	return int( ($_[0]+512*1024)/1024/1024);
}

##############################################################################

sub interactive_mode
{
	die( "No file(s).\n") unless defined($ARGV[0]) && scalar( grep{ ! -f $_} @ARGV)==0;

	my @files = get_all_names( @ARGV);
	if( scalar(@files)>1 ) {
		print "Ktoré súbory (a v akom poradí) spojiť?\n(* znamená všetky v uvedenom poradí):\n";
		print_choices( \@files, '>> ');
		my @numbers = read_choices( scalar @files);
		@files = map { $files[$_-1] } @numbers;
	}
	if( scalar(@files)==0 ) {
		print "Nie je žiaden súbor na spracovanie.\n";
		pause;
		exit(1);
	}
	if( scalar(@files)==1 ) {
		print "Bude sa spracúvať súbor:\n";
	}else {
		print "Budú sa spájať súbory:\n";
	}
	print join("\n",@files), "\n";

	my ($video,$audio,$subtitle,$param) = get_streams( $files[0]);
	my @map;
	my @streams = ( ['Video streamy', $video],
					['Audio streamy', $audio],
					['Titulky', $subtitle],
		);
	my %jobinfo;
	for my $stream (@streams) {
		my ($stream_name,$list) = @$stream;
		$jobinfo{$stream_name} = [];
		if( scalar(@$list) > 0 ) {
			print "\n$stream_name:\n";
			if( scalar(@$list)>1 || $stream_name eq 'Titulky' ) {
				print_choices( $list, "Ktoré streamy spracovať? (* = všetky)\n>> ");
				foreach ((read_choices( scalar @$list))) {
					my $id = get_stream_id( $stream_name, $list, $_-1);
					push @map, $id;
					push @{$jobinfo{$stream_name}}, $id;
				}
				#my @num = read_choices( scalar @$list);
				#push @map, get_stream_id( $stream_name, $list, $_-1) foreach (@num);
				#$have_subtitles = 1 if $stream_name eq 'Titulky' && scalar @num > 0;
			}else {
				print_choices( $list);
				my $id = get_stream_id( $stream_name, $list, 0);
				push @map, $id;
				push @{$jobinfo{$stream_name}}, $id;
			}
		}
	}

	#print "\nMapovanie: ", join(' ',@map), "\n";

	print "\n*** Parametre konverzie ***\n";
	print "Vyber stupeň video kvality - High, Normal, Copy\nh n c >> ";
	my $video_mode = lc( read_answer( 'HhNnCc') );
	print "Vyber stupeň audio kvality - AAC, Copy\na c >> ";
	my $audio_mode = lc( read_answer( 'AaCc') );
	
	my ($start_time,$duration,$end_time);
	print "Upraviť začiatok alebo koniec záznamu\na n >>";
	if( lc( read_answer( 'AaNn')) eq 'a' ) {
		print "\n\nPouži FFPLAYER na zistenie značky začiatku a konca\nZačiatok posunúť o [s] (default 0): ";
		
		$start_time = <STDIN>;
		exit 1 if $Signal;
		chomp $start_time;
		$start_time =~ s/,/./g;
		print "Koniec na pozícii [s] (default 0):";
		$end_time = <STDIN>;
		exit 1 if $Signal;
		chomp $end_time;
		$end_time =~ s/,/./g;
		
		$start_time = $param->{start} unless $start_time =~ m/^[0-9.]+$/;
		if( defined($end_time) && $end_time =~ m/^[0-9.]+$/ ) {
			$duration = $end_time - $start_time;
		}
		$start_time -= $param->{start};
		$start_time = int($start_time*1000+0.5)/1000;
		$start_time = seconds2hms( $start_time) if $start_time>0;
	}else {
		$start_time = 0;
	}
	
	if( scalar @{$jobinfo{'Titulky'}} > 0 ) {
		$jobinfo{has_subtitles} = 1;
		$jobinfo{output_container} = 'mkv';
	}else {
		$jobinfo{output_container} = 'mp4';
	}

	my $cmd = "\"$ffmpeg\" -hide_banner -y";
	
	$cmd .= " -ss \"$start_time\"" if $start_time ne '0';
	$cmd .= " -t $duration" if defined $duration;

	if( scalar @files > 1 ) {
		$cmd .= " -i \"concat:" . join('|',@files) . "\"";
	}else {
		$cmd .= " -i \"$files[0]\"";
	}

	my %video_param = (
		h => [ 'libx265', '-x265-params', 'crf=24' ],
		n => [ 'libx265', '-x265-params', 'crf=26' ],
		c => [ 'copy' ],
	);
	my %audio_param = (
		a => [ 'aac' ],
		c => [ 'copy' ],
	);
	my @filter_param;
	if( $video_mode ne 'c' ) {
		if( $video->[0] =~ m/, (\d+)x(\d+)[ ,]/ ) {
			my ($w,$h) = ($1,$2);
			if( $w > 1280 ) {
				# prefer round slightly up
				$h = int( $h*1280/$w/8 + 0.7 ) * 8;
				$w = 1280;
				@filter_param = ( "-vf", "scale=w=$w:h=$h" );
			}
		}else {
			@filter_param = ( "-vf", "scale=w='min(iw,1280):h=-1'" );
		}
	}

	my ($dir,$name) = fnsplit($files[0]);
	$name =~ s/(.+)(\.[^.]+)$/$1-converted.$jobinfo{output_container}/;
	my $dst = fnmerge($dir,$name);

	$cmd .= " -c:v ".join(' ',map{"\"$_\""}@{$video_param{$video_mode}});
	$cmd .= " -c:a ".join(' ',map{"\"$_\""}@{$audio_param{$audio_mode}});
	$cmd .= " -scodec copy" if defined $jobinfo{has_subtitles};
	$cmd .= " ".join(' ',map{'-map '.$_}@map);
	$cmd .= " ".join(' ',map{"\"$_\""}@filter_param);
	$cmd .= " \"$dst\"";
	print "\nCommand:\n$cmd\n\n";

	# Write job file:

	my $jobfile = create_job_file( $jobpath); # nájde voľné meno pre job-NNNNNN.temp; vráti meno
	{
		my (@out,$k);
		push @out, map {"!SOURCE=$_"} @files;
		push @out, "!DESTINATION=$dst";
		foreach $k (keys %jobinfo) {
			if( ref $jobinfo{$k} eq 'ARRAY' ) {
				push @out, "!INFO=$k: ".join(', ',@{$jobinfo{$k}}) if scalar(@{$jobinfo{$k}})>0;
			}else {
				push @out, "!INFO=$k: ".$jobinfo{$k};
			}
		}
		# https://stackoverflow.com/questions/44351606/ffmpeg-set-the-language-of-an-audio-stream/44351749
		# https://en.wikipedia.org/wiki/List_of_ISO_639-2_codes
		push @out, "!#META-HELP= -metadata:s:a:N language=ces -metadata:s:a:N title=\"Čeština\"";
		push @out, "!#META-HELP= -metadata:s:a:N language=slk -metadata:s:a:N title=\"Slovenčina\"";
		push @out, "!#META-HELP= -metadata:s:a:N language=eng -metadata:s:a:N title=\"Angličtina\"";
		push @out, "!#META-HELP= -metadata:s:a:N language=rus -metadata:s:a:N title=\"Ruština\"";
		push @out, "!#META-HELP= -metadata:s:a:N language=deu -metadata:s:a:N title=\"Nemčina\"";
		push @out, $cmd;
		write_file( $jobfile, \@out);
	}
	my $jobready = $jobfile=~s/\.temp/.ready/r;
	move $jobfile, $jobready;

	print "Hotovo. Konverzia je pripravená v súbore $jobready.\n";
	pause;
}

sub player_mode
{
	die( "No file(s).\n") unless defined($ARGV[0]) && scalar( grep{ ! -f $_} @ARGV)==0;

	my @files = get_all_names( @ARGV);
	if( scalar(@files)>1 ) {
		print "Ktoré súbory (a v akom poradí) prehrať?\n(* znamená všetky v uvedenom poradí):\n";
		print_choices( \@files, '>> ');
		my @numbers = read_choices( scalar @files);
		@files = map { $files[$_-1] } @numbers;
	}
	if( scalar(@files)==0 ) {
		print "Nie je žiaden súbor na prehrávanie.\n";
		pause;
		exit(1);
	}
	if( scalar(@files)==1 ) {
		print "Bude sa prehrávať súbor:\n";
	}else {
		print "Budú sa prehrávať súbory:\n";
	}
	print join("\n",@files), "\n";

	$ENV{SDL_AUDIODRIVER} = 'directsound';
	
	my $param = "-hide_banner -stats -vf scale=w='min(iw,800):h=-1'";

	if( scalar @files > 1 ) {
		$param .= " -i \"concat:" . join('|',@files) ."\"";
	}else {
		$param .= " -i \"$files[0]\"";
	}
	
	my $cmd = "\"$ffplay\" $param";
	print STDERR "$cmd\n";
	print "\nOvládanie: s = step 1 frame, left/right = seek 10s, down/up = seek 1m, page down/up = seek 10m\n";
	
	$cmd = encode_win($cmd);
	qx# $cmd #;
}

sub daemon_mode
{
	LOGstart( fnmerge($jobpath,'FFMASTER.log'), encoding => 'Windows-1250', stderr => 1);
	LOG( "Start.");
	for(;;) {
		exit 1 if $Signal;

		my @readyjobs = sort
			grep /^job-\d{6}\.ready$/,
			map {chomp;$_}
			@{read_dir( $jobpath)};
		last unless scalar @readyjobs > 0;
		foreach my $job (@readyjobs) {
			print "\n\n======================\n## $job ##\n======================\n";
			LOG( "Start processing $job", '-'x25);
			my $t1 = DateTime->now( time_zone => 'Europe/Bratislava');
			print STDERR ( format_datetime( $t1), "\n");
			
			my $jobfile = fnmerge($jobpath,$job);
			my $cmd;
			my @source_files;
			my $destination_file;
			my %jobinfo = ( source_files=>[]);
			{	my @lines;
				if( !read_file( $jobfile, to=>\@lines, die=>0) ) {
					LOG( "Cannot open $jobfile: $!");
					$jobfile = change_job_state( $jobfile, '.ready', '.failed');
					next;
				}
				$cmd = join( ' ', grep !/^!/,@lines);
				foreach (grep /^!/,@lines) {
					push @{$jobinfo{source_files}}, $1 if m/^!SOURCE=(.+)/;
					$jobinfo{destination_file} = $1 if m/^!DESTINATION=(.+)/;
					if( m/^!INFO=(.+)/ && $1 =~ m/^([^:]+): (.+)/ ) {
						$jobinfo{$1} = $2;
					}
				}
			}
			LOG( "cmd=$cmd");
			foreach my $var ($cmd =~ m/%([a-zA-Z0-9_]+)%/g) {
				if( defined $ENV{$var} ) {
					my $subst = decode_win( $ENV{$var});
					$cmd =~ s/%[a-zA-Z0-9_]+%/$subst/g;
				}
			}
			LOG( "resolved cmd=$cmd");
			LOG( "Video streams: $jobinfo{'Video streamy'}") if defined $jobinfo{'Video streamy'};
			LOG( "Audio streams: $jobinfo{'Audio streamy'}") if defined $jobinfo{'Audio streamy'};
			LOG( "Subtitles: $jobinfo{'Titulky'}") if defined $jobinfo{'Titulky'};
			LOG( "Writing to '$jobinfo{destination_file}'") if defined $jobinfo{destination_file};
			$jobfile = change_job_state( $jobfile, '.ready', '.doing');
			$cmd = encode_win($cmd);
			my @result = map{chomp;$_} qx# $cmd 2>&1 #;
			# open my $ph, '-|', "$cmd 2>&1";
			# while(<$ph>) {
			#	print "$_";
			#	chomp;
			#	push @result, $_;
			# }
			my $msg = return_exec_error();
			if( defined $msg ) {
				LOGcat( \@result);
				LOG( $msg);
				$jobfile = change_job_state( $jobfile, '.doing', '.failed');
			}else {
				LOG( "Finished processing $job");
				if( scalar(@{$jobinfo{source_files}})>0 && defined($jobinfo{destination_file}) ) {
					my ($size_src,$size_dst) = (0,get_file_size($jobinfo{destination_file}));
					$size_src += get_file_size( $_) foreach @{$jobinfo{source_files}};
					LOG( "size of source: ", round2mb($size_src), " MB, size of result: ", round2mb($size_dst), " MB");
				}
				$jobfile = change_job_state( $jobfile, '.doing', '.done');
			}
			
			my $t2 = DateTime->now( time_zone => 'Europe/Bratislava');
			print STDERR ( format_datetime( $t2), "\n");
			LOG( "Duration ", format_duration( $t2->jd()-$t1->jd()));
			LOG( '='x59);
		}
	}
	LOG( "Done.");
}

__END__

=pod

=encoding UTF-8

=for comment
c:\Strawberry\perl\bin\pod2html.bat --noindex --outfile=C:\mediatools\FFMASTER.html C:\mediatools\FFMASTER.pl

=head1 Názov

B<FFMASTER.pl> - interaktívna tvorba úloh pre konverziu video súborov / spracovanie pripravených úloh

=head1 Verzia

Táto verzia je určená pre beh pod Strawberry Perl (pod Windows).

=head1 Príklad 1 - interaktívna príprava konverzií

C<FFMASTER.pl fileA [fileB ...]>

Ak názov (názvy) súborov obsahujú číslo, vytvorí sa vstupná množina zo všetkých podobne číslovaných súborov v zadaných adresároch.
Ak vstupná množina pozostáva z viac než jedného súboru, konvertovať sa bude spojenie súborov. Ktoré súbory z množiny naozaj vstúpia do spájania, a v akom poradí, určí interaktívne používateľ.

B<POZOR:> Všetky spájané súbory musia mať rovnaké usporiadanie streamov!

Ak je na vstupe viac než jeden video stream, alebo viac než jeden audio stream alebo aspoň jedny titulky (po vynechaní streamov pre telesne postihnutých a pod.), vyberá si používateľ ktoré streamy chce preniesť do výstupného súboru.

Na záver, po voľbe konverzie videa a audia, vytvorí FFMASTER job (súbor C<job-NNNNNN.ready> v určenom adresári) a končí.

=head1 Príklad 2 - dávkové spracovanie úloh

C<FFMASTER.pl --go>

FFMASTER sa naštartuje v dávkovom režime, kedy postupne spracúva všetky pripravené job-y (C<job-NNNNNN.ready>) a skončí až po tom, ako sú všetky spracované.

=head1 Job súbor

Job súbor, pripravený na vykonanie, má názov C<job-NNNNNN.ready>. Práve spracúvaný job súbor má názov C<job-NNNNNN.doing>. Bezchybne vykonaný job súbor má názov C<job-NNNNNN.done>. Ak spracovanie skončilo chybou, má súbor názov C<job-NNNNNN.failed>.

C<NNNNNN> v názve súboru je číslo.

Obsah súboru je tvorený jedným (alebo viacerými???) príkazmi pre shell (cmd). Pred tým, ako sa obsah odovzdá shellu na vykonanie, urobia sa substitúcie: každý výskyt C<%varname%> sa nahradí obsahom príslušnej environment premennej, s výnimkou prípadu C<%%>.

=head1 Príklad 3 - prehrávanie médií

C<FFMASTER.pl --play fileA [fileB ...]>

Ponúkne možnosť zostaviť množinu súborov na prehrávanie, podobne ako v príklade #1 a tie potom začne prehrávať v zmenšenom okne. V inom okne sa zobrazuje práve prehrávaná pozícia v súbore (je to prvé číslo na poslednom riadku).

Zadaním počiatočnej a/alebo koncovej pozície prehrávania do FFMASTER sa dosiahne orez pred konverziou.

=cut
