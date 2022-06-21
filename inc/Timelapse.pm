package Timelapse;

use strict;
use Exiftool;
use Log qw(logSystem timeLog);
use ImageBlender;
use Forker;

# this is the prefix that we put on the front of newly created images for the output sequence
our $SEQUENCE_IMAGE_PREFIX = "LRT_";

sub validate() {
  # we need ffmpeg

  die <<END
ERROR

ffmpeg is not installed

visit https://ffmpeg.org

and install it to use this tool
END
    unless(system("which ffmpeg >/dev/null") == 0);
}

# this renders an image sequence from the given dirname into a video file
# for now, just full resolution ProRes high quality
# if successful, the filename of the rendered video is returned
sub render($$) {
  my ($image_sequence_dirname, $exif) = @_;

  opendir my $source_dir, $image_sequence_dirname or die "cannot open source dir $image_sequence_dirname: $!\n";

  my $test_image;

  # read all files at the first level of the source dir
  foreach my $filename (readdir $source_dir) {
    next if($filename =~ /^[.]/);
    $test_image = $filename;
    last;
  }

  closedir $source_dir;

  # XXX handle error here
  my $exif = Exiftool::run("$image_sequence_dirname/$test_image");

  my $image_width = $exif->{ImageWidth};
  my $image_height = $exif->{ImageHeight};

  if($image_width == 0 || $image_height == 0) {
      # XXX problem
  }

  # calculate aspect ratio from width/height
  my $aspect_ratio = get_aspect_ratio($image_width, $image_height);

  my $output_video_filename = $image_sequence_dirname;

  # remove the sequence image prefex if it happens to be part of the video filename
  $output_video_filename =~ s/$SEQUENCE_IMAGE_PREFIX//;

  # prepend the format and file extention to the end of the filename
  $output_video_filename .= "_ProRes-444_Rec.709F_OriRes_30_UHQ.mov";

  if(-e $output_video_filename) {
    print("$output_video_filename already exists, cannot render\n");
  } else {
    # render
    # full res, ProRes high quality
    my $ffmpeg_cmd = "ffmpeg -y -r 30 -i $image_sequence_dirname/$SEQUENCE_IMAGE_PREFIX%05d.tif -aspect $aspect_ratio -c:v prores_ks -pix_fmt yuv444p10le -threads 0 -profile:v 4 -movflags +write_colr -an -color_range 2 -color_primaries bt709 -colorspace bt709 -color_trc bt709 -r 30 ";

    # add exif
    foreach my $exif_key (keys %$exif) {
      my $exif_value = $exif->{$exif_key};
      $ffmpeg_cmd .= "-metadata '$exif_key=$exif_value' ";
    }

    $ffmpeg_cmd .= $output_video_filename;

    if (logSystem($ffmpeg_cmd) == 0) {
      print("render worked, removing image sequence dir\n");
      return $output_video_filename;
    } else {
      print("render failed :("); # why?
    }
  }
}

# blends the sequence in $source_dirname so that each image is blended with
# the given weight curve across $merge_frame_size images, except for those
# at the edges, which will be blended with at least half that many.
# the merge frame is centered on each output frame.
sub curve_blend($$$$$$) {
  my ($merge_frame_size,	# integer giving the size of the blending window
      $weight_curve,		# weight curve object
      $source_dirname,		# dirname of the source image sequence
      $max_children,		# max children object
      $should_run,		# boolean should actually or not
      $should_log) = @_;	# boolean should log blending curves for each output frame

  my $curve_name = $weight_curve->{name};
  my $curve_blender_name = $weight_curve->{blender};

  # dirname for newly created blended image sequence
  my $new_dirname = $source_dirname."-$curve_blender_name-$curve_name-merge";

  $new_dirname =~ s/[.]/_/g;	# change dots in floating point numbers to underscores

  if (-d $new_dirname) {
    print "$new_dirname already exists, trying to finish\n";
    print "\t run\n  rm -rf $new_dirname\n\t to remove and start over \n";
#    exit;
  } elsif($should_run) {
    # make the new output dir
    mkdir $new_dirname || die "$!\n";
  }

  my $source_file_list = &Timelapse::read_dir($source_dirname);

  my $image_blender_list = [];

  for (my $i = 0 ; $i < scalar(@$source_file_list) ; $i++) {
    my $images_to_blend = [];

    # start index to center
    my $start_index = int($i-$merge_frame_size/2) + 1; # XXX related to start @ 1?

    # XXX here we could also allow a different start index,
    # i.e. an enum of LEFT, RIGHT, and CENTER n

    for (my $j = 0 ; $j < $merge_frame_size ; $j++) {
      my $idx = $start_index+$j;
      # ignore frames in our blend window that go off the ends fo the sequence
      # these output frames will simply have less frames blended into them
      next if($idx < 0);
      next if($idx >= scalar(@$source_file_list));

      my $weighted_image =
	WeightedImage->new("$source_dirname/$source_file_list->[$idx]",
			   $weight_curve->value_at_position($j));

      push @$images_to_blend, $weighted_image;
    }
    # is LRT necessary here vv ?
    my $filename = sprintf("$SEQUENCE_IMAGE_PREFIX%05d.tif", $i+1); # XXX start at 1

    unless(-e "$new_dirname/$filename") {
      my $image_blender = ImageBlender->new("$new_dirname/$filename");
      $image_blender->setImageList($images_to_blend);

      push @$image_blender_list, $image_blender;
    }
  }

  ImageBlender::logImageBlenderList($image_blender_list) if($should_log);

  # then fork and blend them gaussianly in parallel

  if($should_run) {
      Forker::run($image_blender_list, $max_children);

      return $new_dirname;
  }
}

# reads the files at the top level of the given directory, returning the names
# in a list
sub read_dir($) {
  my ($source_dirname) = @_;

  opendir my $source_dir, $source_dirname or die "cannot open source dir: $!\n";

  my $source_file_list = [];

  # XXX this fails when some files in the dir are not images, fix that

  # read all files at the first level of the source dir
  foreach my $filename (sort readdir $source_dir) {
    next if($filename =~ /^[.]/);
    push @$source_file_list, $filename; # XXX notice filetype here
  }				       # use it below instead of tiff
                                       # also check start index
  closedir $source_dir;

  return $source_file_list;
}

sub get_aspect_ratio($$) {
  my ($width, $height) = @_;

  my $ratio_width = $width/$height;
  my $ratio_height = 1;

  if (is_int($ratio_width)) {
    return "$ratio_width/$ratio_height";
  } else {
    # not sure we need ints here
    # need to multiply
    my ($a, $b) = recurse_to_find_integers($ratio_width, $ratio_height, 2);
    return "$a/$b" if(defined $a && defined $b);
    return "$width/$height";	# unable to find integers, return original values
  }
}

sub recurse_to_find_integers($$$) {
  my ($left, $right, $multiplier) = @_;

  if(is_int($left*$multiplier) && is_int($right*$multiplier)) {
    return ($left*$multiplier, $right*$multiplier);
  } else {
    return undef if($multiplier > 1000);
    return recurse_to_find_integers($left, $right, $multiplier+1);
  }
}

sub is_int($) {
  my ($value) = @_;

  return $value == int $value;
}

sub extract_image_sequence_from_video($$$$) {
  my ($video_filename, $output_dir, $img_prefix, $image_type) = @_;

  my $output_dirname = $video_filename;
  if($video_filename =~ m~/([^/]+)$~) {
    $output_dirname = $1;	# remove path
  }

  timeLog("foo output_dirname $output_dirname");
  timeLog("bar output_dir $output_dir");
  $output_dirname =~ s/[.][^.]+$//; # remove any file extension


  $output_dirname = "$output_dir/$output_dirname" if($output_dir ne "");

  mkdir $output_dirname;	# errors?

  logSystem("ffmpeg -i $video_filename $output_dirname/$img_prefix"."%05d.$image_type");

  return $output_dirname;	# the dirname of the image sequence
}

1;

