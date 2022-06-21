package SmoothRampBlender;

use strict;
use Timelapse;
use LinearCurve;
use Getopt::Long;
use GaussianTransition;

sub new {
  my ($class) = @_;
  my $self =
    {
     name => 'smooth-ramp'
    };

  return bless $self, $class;
}

sub description() {
  my ($self) = @_;
  my $name = $self->{name};
  return <<END
   The $name blender blends the input frame sequence for each output frame
   weighted with a gaussian smoothed ramp between the min and max values provided.
   The min weight is applied the the oldest input frame, the max weight is applied
   to the newest input frame.

   This produces a different look than the bell-curve blend, where either the start or
   the end of the blend will stand out more.
END
}

sub usage() {
  my ($self) = @_;
  my $name = $self->{name};
  return <<END
Usage for the $name blender:

   --size n             - the size of the blend window in frames
   --max n              - weight for most recent frame
   --min n              - weight for oldest frame
   --sequence directory - the name of the directory containing the input image sequence
END
}

sub parseArgs() {
  my ($self) = @_;

  # the number of images to blend into each output image
  my $merge_frame_size;

  # max bell curve value
  my $max_value;

  # min bell curve value
  my $min_value;

  # the dirname of the initial image sequence
  my $source_dirname;

  GetOptions("size=i" => \$merge_frame_size,
	     "max=f" => \$max_value,
	     "min=f" => \$min_value,
	     "sequence=s" => \$source_dirname);

  return "missing required args" unless(defined $merge_frame_size &&
					defined $source_dirname &&
					defined $max_value &&
					defined $min_value);

  if($max_value <= $min_value) {
    return "max_value $max_value is greated than min_value $min_value\n";
  }

  $source_dirname =~ s~/$~~; # remove any possible trailing slash from the source dirname
  
  $self->{merge_frame_size} = $merge_frame_size;
  $self->{source_dirname} = $source_dirname;
  $self->{max_value} = $max_value;
  $self->{min_value} = $min_value;

  $self->{curve} = GaussianTransition->new($merge_frame_size,
					   $min_value,
					   $max_value);
  $self->{curve}{blender} = $self->{name};

  return undef;
}

sub blendSequence() {
  my ($self) = @_;

  $self->{blended_sequence_dirname} =
    Timelapse::curve_blend($self->{merge_frame_size},
			   $self->{curve},
			   $self->{source_dirname},
			   $self->{max_children},
			   1,	# run
			   0);	# don't log
}

sub logBlendInfo() {
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
    my $exif = {};		# XXX fix this
    my $video_filename = Timelapse::render($newly_blended_sequence_dirname, $exif);
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

