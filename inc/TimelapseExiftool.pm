package TimelapseExiftool;

use lib '/opt/local/lib/perl5/site_perl/5.22'; # this sucks :(
use Term::ANSIColor qw(:constants);
use Text::CSV qw( csv );
use JSON;

$Term::ANSIColor::AUTORESET = 1;

# this module deals with generating exiftool json files from timelapses:
#  - a directory of raw files
#  - single .7z archive of raw files
#  - a directory of .7z archives

sub validate() {
  # we need exiftool

  die <<END
ERROR

exiftool is not installed

visit https://exiftool.org

and install it to use this tool
END
    unless(system("which exiftool >/dev/null") == 0);
}

sub new {
  my ($class) = @_;

  my $base =
    {
     'raw_filetypes' , ['ARW', 'DNG'],
     'temp_path' , '/Volumes/op/tmp/'
    };

  return bless $base, $class;
}


sub process_filename() {
  my ($self, $filename) = @_;

  if (-d $filename) {
    # it a directory

    my $raw_count = $self->number_of_raw_images_in_directory($filename);

    my $sevenz_count = `ls $filename/*.7z 2>/dev/null | wc -l`;
    chomp $sevenz_count;
    if ($raw_count != 0 && $sevenz_count != 0) {
      die "dir $filename has both .7z and raw files, cannot process\n";
    }
    if ($raw_count != 0) {
      # process folder of raw files
      print $self->json_for_raw_dir($filename);
    } elsif ($sevenz_count != 0) {
      # process folder of .7z archives
      $self->process_7z_dir($filename);
    } else {
      warn "no 7z or raw files found in $filename\n";
    }
  } elsif (-f $filename || $filename =~ /[.]7z$/) {
    # process an individual 7z archive
    print $self->process_7z_archive($filename);
  } else {
    warn "cannot process $filename\n";
  }
}

sub number_of_raw_images_in_directory() {
  my ($self, $directory) = @_;

  my $ret = 0;

  foreach my $raw_filetype (@{$self->{raw_filetypes}}) {
    my $raw_count = `ls $directory/*.$raw_filetype 2>/dev/null | wc -l`;
    chomp $raw_count;
    $ret += $raw_count;
  }
  return $ret;
}

# this writes .json files for each .7z file in the dir
sub process_7z_dir() {
  my ($self, $dirname) = @_;

  timeLog(MAGENTA, "processing 7z dir ", BLUE, "$dirname", RESET);

  opendir my $dir, $dirname or die "cannot open dir: $!\n";
  my $pwd = `pwd`;
  chomp $pwd;
  foreach my $filename (readdir $dir) {
    next unless($filename =~ /[.]7z$/i); # process only .7z archives
    $self->process_7z_archive("$dirname/$filename");
  }
}

sub process_7z_archive() {
  my ($self, $filename) = @_;
  timeLog(MAGENTA, "processing 7z archive ", BLUE, "$filename");
  my $json_filename = $filename;
  $json_filename =~ s/[.]7z$/.json/;
  if (-e $json_filename) {
    # skip if a json file already exists
    timeLog(MAGENTA, "skipping ", BLUE, "$filename", RESET, " a json file already exists");
  } else {
    my $json = $self->json_for_7z_archive($filename);
    chdir $pwd;
    open(JS, ">$json_filename") || die "cannot open $json_filename: $!\n";
    print JS $json;
    close JS
  }
}

# this returns a json string for the given 7z archive
sub json_for_7z_archive() {
  my ($self, $archive_filename) = @_;	# needs to be an exact path (not relative)

  if($archive_filename !~ m~^/~) {
    my $pwd = `pwd`;
    chomp $pwd;
    $archive_filename = "$pwd/$archive_filename";
  }

  my $raw_files = {};

  foreach my $raw_filetype (@{$self->{raw_filetypes}}) {
    my $command = "7za l $archive_filename | grep -i $raw_filetype";

    open my $fh, "$command |";
    while (<$fh>) {
      $raw_files->{$1} = 1 if (m~\s+([\w\d/_-]+[.]$raw_filetype)~i);
    }
    close $fh;
  }
#  print "we have ",join("\n", keys %$raw_files),"\n";

  my $tmp_filename = "$self->{temp_path}/$$"."_dslwfje/";
  mkdir $tmp_filename or die "could not make temp filename $tmp_filename: $!\n";
  chdir $tmp_filename;

  my $total_exif_map = {};

  timeLog(MAGENTA, "expanding ", BLUE, "$archive_filename");

  system("7za x $archive_filename ".join(' ', keys %$raw_files)." > /dev/null");

  timeLog(MAGENTA, "running exiftool", RESET);

  foreach my $raw_filename (keys %$raw_files) {
    my $new_exif_map = $self->run_exiftool($raw_filename);
    $self->process_exif($total_exif_map, $new_exif_map);
  }
  my $ret = JSON->new->pretty->encode($total_exif_map);

  system("rm -rf $tmp_filename");

  return $ret;
}

# this returns a json string for the given raw folder
sub json_for_raw_dir() {

  my ($self, $dirname) = @_;

  opendir my $dir, $dirname or die "cannot open dir: $!\n";

  my @initial_file_list = ();

  my $total_exif_map = {};

  foreach my $filename (readdir $dir) {
    my $is_raw = 0;
    foreach my $raw_filetype (@{$self->{raw_filetypes}}) {
      $is_raw = 1 if($filename =~ /$raw_filetype$/i);
    }
    next unless $is_raw;
    my $new_exif_map = $self->run_exiftool("$dirname/$filename");
    $self->process_exif($total_exif_map, $new_exif_map);
  }
  closedir $dir;

  return JSON->new->pretty->encode($total_exif_map);
}

# this adds tallies for a new exif map to the totals
sub process_exif() {
  my ($self, $total_exif_map, $new_exif_map) = @_;
  foreach my $key (keys %$new_exif_map) {
    next if($key eq 'Thumbnail Image');	# skip binary data
    next if($key eq 'Preview Image');
    next if($key eq 'Tiff Metering Image');
    my $new_value = $new_exif_map->{$key};
    if(exists $total_exif_map->{$key}{$new_value}) {
      $total_exif_map->{$key}{$new_value}++;
    } else {
      $total_exif_map->{$key}{$new_value} = 1;
    }
  }
}

# returns a basic map of the exiftool output for the given filename
sub run_exiftool() {
  my ($self, $filename) = @_;
  my $ret = {};

  #  open my $fh, "exiftool -csv $filename |";

  my $csv = Text::CSV->new ({ binary => 1, auto_diag => 1 });
  open my $fh, "exiftool -csv $filename |" or die $!;

  # first row is keys
  my $row1 = $csv->getline ($fh);
  # second row is values
  my $row2 = $csv->getline ($fh);

  # no other rows
  
  my $exif_data = {};

  for(my $i = 0 ; $i < scalar @$row1 ; $i++) {
    $exif_data->{$row1->[$i]} = $row2->[$i];
  }

  close $fh;

  return $exif_data;
}

# this takes a given exif json file and applies constant values in it
# to a given file (assumed to be a video, but any exiftool writable format should work)
sub apply_exif_to_video() {
  my ($self, $exif_data, $video_filename) = @_;

  # this is the master json file from the entire sequence
#  my $exif_data = read_json_from($exif_json_filename);

  my @row1 = ();
  my @row2 = ();
  my $rows = [\@row1, \@row2];

  foreach my $key (keys %$exif_data) {

    my $exif_data_for_key = $exif_data->{$key};

    if (scalar keys %$exif_data_for_key == 1) {
      # here all images in the sequence had the same key/value pair
      # we can embed these in the video
      my $single_value = (keys %$exif_data_for_key)[0];
      push @row1, $key;
      push @row2, $single_value;
      if($key eq 'LensSpec') {
	push @row1, 'Lens';	# this makes the lens show up in Lightroom :)
	push @row2, $single_value;
      } elsif($key eq 'ExposureTime') {
	push @row1, 'Exposure';	# exposure still isn't showing up :(
	push @row2, $single_value;
	# try 'ShutterSpeed'?
      }
    } else {
      # here there is more than one setting for this value during the sequence.
      # ISO, f/stop, etc.
      # Need a good way to represent these in the video, maybe some kind of synthesis?
    }
  }

  push @row1, "SourceFile";	# exiftool barfs without this being just right
  push @row2, $video_filename;

  my $csv_filename = "/tmp/$$"."_file.csv"; # temporary csv filename

  csv (in => $rows, out => $csv_filename); # write temporary csv file

  # use exiftool to embed these values into the given video file
  if(system("exiftool -overwrite_original -csv=$csv_filename $video_filename") == 0) {
    # worked
  } else {
    # failed XXX handle this better
  }

  system("rm $csv_filename");
}

# this takes a given dir with exif json files, and another dir with video files,
# and appies the exif from the json files to the appropriate video files by filename
sub exify_dirs() {
  my ($self, $json_dirname, $video_dirname) = @_;

  opendir my $json_dir, $json_dirname or die "cannot open dir: $!\n";

  my @json_filenames = ();
  my $exif_map = {}; # map from basename to full exif data for that sequence

  timeLog("reading json files");

  foreach my $filename (readdir $json_dir) {
    if ($filename =~ /^([^.]+).json/) {
      my $basename = $1;
      timeLog(MAGENTA, "reading", BLUE, " $json_dirname/$filename", RESET);
      # don't load here, just keep track of what files we have
      push @json_filenames, $basename;
    }
  }
  closedir $json_dir;

  timeLog("processing video files");

  opendir my $video_dir, $video_dirname or die "cannot open dir: $!\n";
  foreach my $filename (readdir $video_dir) {
    next unless($filename =~ /[.]mov$/ || $filename =~ /[.]mp4$/);
    foreach my $basename (@json_filenames) {
      if ($filename =~ /^$basename/) {
	my $full_video_path = "$video_dirname/$filename";
	my $existing_exif = $self->run_exiftool($full_video_path);
	if(exists $existing_exif->{Model}) {
	  timeLog("skipping $filename, it appears to already have exif");
	} else {
	  timeLog("applying exif data to $filename");

	  my $json_data = $exif_map->{$basename};
	  unless(defined $json_data) {
	    $json_data = read_json_from("$json_dirname/$basename.json");
	    $exif_map->{$basename} = $json_data;
	  }

	  $self->apply_exif_to_video($json_data, $full_video_path);
	}
      }
    }
  }
  closedir $video_dir;
}

sub timeLog {
  my $d = `date "+%r"`;
  chomp $d;
  print YELLOW, "      $d", RESET, " - ", @_, "\n";
}

sub read_json_from {
  my ($filename) = @_;

  my $json_text = do {
    open(my $json_fh, "<:encoding(UTF-8)", $filename)
      or warn ("Can't open \"$filename\": $!\n");
    local $/;
    <$json_fh>
  };

  my $ret = undef;
  if (defined $json_text) {
    eval {
      $ret = JSON->new->decode($json_text);
      1;
    } or do {
      warn "could not read json from $filename: $@";
    }
  }
  return $ret;
}

sub logSystem {
  my ($cmd) = @_;
  my $d = `date "+%r"`;
  chomp $d;
  print YELLOW, "      $d", RESET, " - ", MAGENTA, "exec", RESET, ": ", BLUE "$cmd\n";
#  die "$!\n" if($ret != 0);

  return system($cmd);
}



return 1;



