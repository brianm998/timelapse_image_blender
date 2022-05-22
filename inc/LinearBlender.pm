package LinearBlender;

use strict;
use Timelapse;
use LinearCurve;
use Getopt::Long;

sub new {
  my ($class) = @_;
  my $self =
    {
     name => 'linear'
    };

  return bless $self, $class;
}

sub description() {
  my ($self) = @_;
  my $name = $self->{name};
  return <<END
   The $name blender blends linearly, meaning that each output frame
   is blended from input frames with equal weight.  So the percentage
   of the output image that represents each input frame is the same for all.
END
}

sub usage() {
  my ($self) = @_;
  my $name = $self->{name};
  return <<END
usage for the $name blender:

   --size num      - size of the blend window in frames
   --sequence name - the name of the input sequence
END
}

sub parseArgs($) {
  my ($self) = @_;

  # the number of images to blend into each output image
  my $merge_frame_size;

  # the dirname of the initial image sequence
  my $source_dirname;

  GetOptions("size=i" => \$merge_frame_size,
	     "sequence=s" => \$source_dirname);

  return "missing required args" unless(defined $merge_frame_size &&
					defined $source_dirname);

  $self->{merge_frame_size} = $merge_frame_size;
  $self->{source_dirname} = $source_dirname;

  $self->{curve} = LinearCurve->new($self->{merge_frame_size});
  $self->{curve}{blender} = $self->{name};

  return undef;			# no error
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
			   LinearCurve->new($self->{merge_frame_size}),
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

