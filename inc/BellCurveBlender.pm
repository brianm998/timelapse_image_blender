package BellCurveBlender;

use strict;
use Timelapse;
use GaussianBellCurve;
use Getopt::Long;

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
   --max n              - weight at top of bell curve
   --min n              - weight at edges of bell curve
   --sequence directory - the name of the directory containing the input image sequence
END
}

sub parseArgs($) {
  my ($self, @argv) = @_;

  # the number of images to blend into each output image
  my $merge_frame_size;

  # XXX make sure max is larger than min (math error later otherwise)
  my $max_value;

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

  return "max_value $max_value is greated than min_value $min_value\n"
    if($max_value <= $min_value);

  $source_dirname =~ s~/$~~; # remove any possible trailing slash from the source dirname
  
  $self->{merge_frame_size} = $merge_frame_size;
  $self->{source_dirname} = $source_dirname;
  $self->{max_value} = $max_value;
  $self->{min_value} = $min_value;

  $self->{curve} = GaussianBellCurve->new($merge_frame_size,
					  $max_value,
					  $min_value);

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
    my $video_filename = Timelapse::render($newly_blended_sequence_dirname);
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

