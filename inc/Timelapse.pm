package Timelapse;

use strict;
use TimelapseExiftool;
use Log qw(logSystem);
use ImageBlender;

# this is the prefix that we put on the front
our $SEQUENCE_IMAGE_PREFIX = "LRT_";

our @EXPORT = qw($SEQUENCE_IMAGE_PREFIX);

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
sub render($) {
  my ($image_sequence_dirname) = @_;

  opendir my $source_dir, $image_sequence_dirname or die "cannot open source dir $image_sequence_dirname: $!\n";

  my $test_image;

  # read all files at the first level of the source dir
  foreach my $filename (readdir $source_dir) {
    next if($filename =~ /^[.]/);
    $test_image = $filename;
    last;
  }

  closedir $source_dir;

  my $exif = TimelapseExiftool->new->run_exiftool("$image_sequence_dirname/$test_image");

  my $image_width = $exif->{ImageWidth};
  my $image_height = $exif->{ImageHeight};

  my $output_video_filename = $image_sequence_dirname;

  # XXX this doesn't work anymore :(
  $output_video_filename =~ s/$SEQUENCE_IMAGE_PREFIX//; # XXX lrt
  $output_video_filename .= "_ProRes-444_Rec.709F_OriRes_30_UHQ.mov";

  if(-e $output_video_filename) {
    print("$output_video_filename already exists, cannot render\n");
  } else {
    # render
    # full res, ProRes high quality
    # XXX LRT XXX
    # XXX hardcoded aspect ratio
    my $ffmpeg_cmd = "ffmpeg -y -r 30 -analyzeduration 2147483647 -probesize 2147483647 -i $image_sequence_dirname/$SEQUENCE_IMAGE_PREFIX%05d.tif -aspect 3:2 -filter_complex \"crop=floor(iw/2)*2:floor(ih/2)*2,zscale=rangein=full:range=full:matrixin=709:matrix=709:primariesin=709:primaries=709:transferin=709:transfer=709:w=$image_width:h=$image_height,setsar=sar=1/1\" -c:v prores_ks -pix_fmt yuv444p10le -threads 0 -profile:v 4 -vendor apl0 -movflags +write_colr -an -color_range 2 -color_primaries bt709 -colorspace bt709 -color_trc bt709 -r 30 $output_video_filename";

    if (logSystem($ffmpeg_cmd) == 0) {
      print("render worked, removing image sequence dir\n");
      return $output_video_filename;
    } else {
      print("render failed :("); # why?
    }
  }
}


# blends the sequence in $source_dirname so that each image is blended gaussianly
# with $merge_frame_size images, except for those at the edges, which will be
# blended with at least half that many.
sub curve_blend($$$$$$) {
  my ($merge_frame_size,
      $weight_curve,
      $source_dirname,
      $max_children,
      $should_run,
      $should_log) = @_;

  my $curve_name = $weight_curve->{name};
  my $curve_blender_name = $weight_curve->{blender};

  # dirname for newly created blended image sequence
  my $new_dirname = $source_dirname."-$curve_blender_name-$curve_name-merge";

  $new_dirname =~ s/[.]/_/g;	# change dots in floating point numbers to underscores

  if (-d $new_dirname) {
    print "$new_dirname already exists, cannot proceed\n";
    print "\t run\n  rm -rf $new_dirname\n\t to continue\n";
    exit;
  } elsif($should_run) {
    # make the new output dir
    mkdir $new_dirname || die "$!\n";
  }

  my $source_file_list = &Timelapse::read_dir($source_dirname);

  #print "got ",join(", ", sort @source_file_list)," files\n";

  my $image_blender_list = [];

  for (my $i = 0 ; $i < scalar(@$source_file_list) ; $i++) {
    my $images_to_blend = [];
    my $start_index = int($i-$merge_frame_size/2) + 1; # XXX related to start @ 1?
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

    my $image_blender = ImageBlender->new("$new_dirname/$filename");
    $image_blender->setImageList($images_to_blend);

    push @$image_blender_list, $image_blender;
  }

  ImageBlender::logImageBlenderList($image_blender_list) if($should_log);

  # then fork and blend them gaussianly in parallel

  if($should_run) {
      ImageBlender::run_job_list($image_blender_list, $max_children);

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


1;


    
