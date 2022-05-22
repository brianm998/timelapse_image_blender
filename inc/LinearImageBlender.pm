package LinearImageBlender;

use strict;

sub new {
  my ($class, @args) = @_;

  # the number of images to blend into each output image
  my $merge_frame_size = shift @args;

  # the dirname of the initial image sequence
  my $source_dirname = shift @args;

  # XXX needs usage and verification of args passed

  my $video_filename =


  my $newly_blended_sequence_dirname =
    curve_blend($merge_frame_size,
		LinearCurve->new($merge_frame_size),
		$source_dirname,
		$max_children);

      
    linear_blend_and_render($merge_frame_size,
			    $source_dirname,
			    $max_children);

  print "rendered video file $video_filename\n";

  my $self =
    {
    };

  return bless $self, $class;
}


1;
