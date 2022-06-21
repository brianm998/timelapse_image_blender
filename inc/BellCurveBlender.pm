package BellCurveBlender;

use strict;
use Timelapse;
use GaussianBellCurve;
use Getopt::Long;
use Log qw(logSystem timeLog);

sub new {
  my ($class) = @_;
  my $self =
    {
     name => 'bell-curve'
    };

  return bless $self, $class;
}

sub description() {
  my ($self) = @_;
  my $name = $self->{name};
  return <<END
   The $name blender blends the input frames for each output frame
   with a gaussian bell curve.  The frame in the middle of the input frame
   sequence for each output frame will be weighted with the max value give.
   The frames at the ends of the input frame sequence will be weighted with
   the min value given.  Use an odd size argument to see these values match
   exactly.

   This provides a gradual appearance and disappearance of features.
END
}

sub usage() {
  my ($self) = @_;
  my $name = $self->{name};
  return <<END
usage for the $name blender:

   --size n             - the size of the blend window in frames
   --sequence directory - the name of the directory containing the input image sequence
   --max n              - weight at top of bell curve, optional defaults to 10
   --min n              - weight at edges of bell curve, optional, defaults to 1
END
}

sub parseArgs($) {
  my ($self, @argv) = @_;

  # the number of images to blend into each output image
  my $merge_frame_size;

  # XXX make sure max is larger than min (math error later otherwise)
  my $max_value = 10;

  my $min_value = 1;

  # the dirname of the initial image sequence
  my $source_dirname;

  # the filename of the input video
  my $input_video_filename;

  GetOptions("size=i" => \$merge_frame_size,
	     "max=f" => \$max_value,
	     "min=f" => \$min_value,
	     "sequence=s" => \$source_dirname,
	     "input-video=s" => \$input_video_filename);

  return "missing required args" unless(defined $merge_frame_size &&
					(defined $source_dirname ||
					 defined $input_video_filename) &&
					defined $max_value &&
					defined $min_value);

  return "max_value $max_value is greated than min_value $min_value\n"
    if($max_value <= $min_value);

  $source_dirname =~ s~/$~~; # remove any possible trailing slash from the source dirname

  $self->{merge_frame_size} = $merge_frame_size;

  $self->{input_video_filename} = $input_video_filename
    if(defined $input_video_filename);
  $self->{source_dirname} = $source_dirname if(defined $source_dirname);
  $self->{max_value} = $max_value;
  $self->{min_value} = $min_value;

  $self->{curve} = GaussianBellCurve->new($merge_frame_size,
					  $max_value,
					  $min_value);

  $self->{curve}{blender} = $self->{name};

  return undef;
}

sub extract_frames($) {
  my ($input_video_filename) = @_;
  # when processing a video, first we need to extract the individual frames
  # and then we set the source_dirname based upon that

  timeLog("extracting frames from $input_video_filename");

  my $output_dir = $input_video_filename;
  $output_dir =~ s~/[^/]+$~~;
  $output_dir = "" if($output_dir eq $input_video_filename); # using cwd

  my $source_dirname =
    Timelapse::extract_image_sequence_from_video($input_video_filename,
						 $output_dir,
						 "LRT_", # XXX constant
						 "tif"); # XXX constant

  if (defined $source_dirname) {
    timeLog("using source_dirname $source_dirname");
    return $source_dirname;

  } else {
    die "failure :(\n";		# XXX make this better
  }
}

sub blendSequence() {
  my ($self) = @_;

  my $should_delete_source_dirname_after_blend = 0;

  unless(exists $self->{source_dirname}) {
    my $input_video_filename = $self->{input_video_filename};
    die("no 'source_dirname' or 'input_video_filename' defined\n")
      unless (defined $input_video_filename);

    timeLog("extracting metadata from $input_video_filename");
    $self->{exif} = Exiftool::run($input_video_filename);

  # XXX actually use this for the rendered video

  # XXX extract information for re-encoding it later, so we can 'match source'
  # - frame rate
  # - codec
  # - color space
  # - other stuff

    my $extracted_dir = extract_frames($input_video_filename);
    die "failure to extract $input_video_filename\n" unless(defined $extracted_dir);
    $self->{source_dirname} = $extracted_dir;

    $should_delete_source_dirname_after_blend = 1;
  }

  $self->{blended_sequence_dirname} =
    Timelapse::curve_blend($self->{merge_frame_size},
			   $self->{curve},
			   $self->{source_dirname},
			   $self->{max_children},
			   1,	# run
			   0);	# don't log

  if($should_delete_source_dirname_after_blend) {
    logSystem("rm -rf $self->{source_dirname}");
  }
}

sub logBlendInfo() {

  # XXX this will fail without a source_dirname

  my ($self) = @_;
    Timelapse::curve_blend($self->{merge_frame_size},
			   $self->{curve},
			   $self->{source_dirname},
			   $self->{max_children},
			   0,	# don't run
			   1);	# log

}

sub renderVideo() {
  my ($self) = @_;

  # render the blended image sequence into a video file
  my $newly_blended_sequence_dirname = $self->{blended_sequence_dirname};
  if(defined $newly_blended_sequence_dirname) {
    my $video_filename = Timelapse::render($newly_blended_sequence_dirname, $self->{exif});
    if(defined $video_filename) {
      $self->{video_filename} = $video_filename;
      return 1;
    }
  }
  return 0;
}

sub deleteBelendedImageSequence() {
  my ($self) = @_;

  my $dirname_to_delete = $self->{blended_sequence_dirname};
  if(defined $dirname_to_delete) {
    system("rm -rf $dirname_to_delete");
  }
}

1;

