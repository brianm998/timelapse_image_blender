package GaussianTrailStreakBlender;

use strict;
use Timelapse;
use LinearCurve;
use Getopt::Long;
use Forker;

sub new {
  my ($class) = @_;
  my $self =
    {
     name => 'streak'		# XXX change thisx
    };

  return bless $self, $class;
}

my $default_fade_out_percentage = 30;

sub description() {
  my ($self) = @_;
  my $name = $self->{name};
  return <<END
   The $name blender allows for introducing a special effect in the middle of a sequence.

   The effect is that the video streaks a bit after the 'start' frame given.
   This streak is a smooth-ramp transition favoring newest frames.

   Before the 'start' frame, no change is made to input frames.

   Up until the 'mid' frame given, this streak will increase to a maximum of 'size' frames.

   Once the 'mid' frame is passed, this streak then smoothly decreases in length up
   until the 'end' frame given.

   After the 'end' frame, no change is made to input frames.

   The speed of the streak reduction between 'mid' and 'end' can be adjusted with the
   'fade' argument.  This is a percentage value that needs to be less than 100 and more than 0.
   The default is $default_fade_out_percentage.
END
}

sub usage() {
  my ($self) = @_;
  my $name = $self->{name};
  return <<END
usage for the $name bleander:

    --start 'frame number'    - start frame of streak
    --mid 'frame number'      - mid frame of streak (where it starts to go away)
    --end 'frame number'      - end frame of streak (where it returns to normal)
    --size 'number of frames' - maximum size of the streak blend frame
    --fade 'percentage'       - set the opacity of the end of the fade (cannot be zero)
    --sequence 'directory'    - directory name containing image sequence to process
END
}

sub parseArgs($) {
  my ($self, @argv) = @_;

  # when to start the blend
  my $start_blend_index;

  # when to transition the blend to closing
  my $mid_blend_index;

  # when to end the blend
  my $end_blend_index;

  # the max size of the blend window
  my $max_blend_window_size;

  # the dirname of the initial image sequence
  my $source_dirname;

  # end value at the bottom of the guassian curve in percentage
  # value must not be zero, but can be 0.000000000001
  # value must be less than 100
  my $fade_out_percentage = $default_fade_out_percentage;

  GetOptions("start=i" => \$start_blend_index,
	     "mid=i" => \$mid_blend_index,
	     "end=i" => \$end_blend_index,
	     "size=i" => \$max_blend_window_size,
	     "fade=f" => \$fade_out_percentage,
	     "sequence=s" => \$source_dirname);

  return "missing required args" unless(defined $start_blend_index &&
					defined $source_dirname &&
					defined $mid_blend_index &&
					defined $end_blend_index &&
					defined $max_blend_window_size);

  unless($start_blend_index < $mid_blend_index && $mid_blend_index < $end_blend_index) {
    return "indices are not in order";
  }

  return "invalid fade out percentage $fade_out_percentage"
    unless($fade_out_percentage > 0 && $fade_out_percentage < 100);

  $source_dirname =~ s~/$~~; # remove any possible trailing slash from the source dirname
  
  $self->{start_blend_index} = $start_blend_index;
  $self->{mid_blend_index} = $mid_blend_index;
  $self->{end_blend_index} = $end_blend_index;
  $self->{max_blend_window_size} = $max_blend_window_size;
  $self->{source_dirname} = $source_dirname;
  $self->{fade_out} = $fade_out_percentage/100;

  return undef;
}

sub blendSequence() {
  my ($self) = @_;

  $self->{blended_sequence_dirname} =
      $self->gaussian_trail_streak(1, 0);
}

sub logBlendInfo() {
  my ($self) = @_;

  $self->gaussian_trail_streak(0, 1);
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

# XXX document this
sub gaussian_trail_streak() {
  my ($self, $should_run, $should_log) = @_;

  my $start_blend_index = $self->{start_blend_index};
  my $mid_blend_index = $self->{mid_blend_index};
  my $end_blend_index = $self->{end_blend_index};
  my $max_blend_window_size = $self->{max_blend_window_size};
  my $source_dirname = $self->{source_dirname};
  my $max_children = $self->{max_children};
  my $lowest_value = $self->{fade_out};

  my $lowest_value_percent = int ($lowest_value*100);

  # dirname for newly created blended image sequence
  my $new_dirname = $source_dirname."-".$self->{name}."-start-$start_blend_index-mid-$mid_blend_index-end-$end_blend_index-max-$max_blend_window_size-fo-$lowest_value_percent-merge";

  $new_dirname =~ s/[.]/_/g;	# change dots in floating point numbers to underscores

  if (-d $new_dirname) {
    print "$new_dirname already exists, cannot proceed\n";
    print "\t run\n  rm -rf $new_dirname\n\t to continue\n";
    exit;
  } elsif ($should_run) {
    # make the new output dir
    mkdir $new_dirname || die "$!\n";
  }

  my $source_file_list = &Timelapse::read_dir($source_dirname);

  # first build up parallel arrays of parameters for each blended frame

  my $image_blender_list = [];

  my $output_image_index = 0;

  my $unroll_window_size = $end_blend_index - $mid_blend_index;
  my $unroll_window_start = $mid_blend_index-$start_blend_index;

  # how fast do we reduce the size of the blend window after mid_blend_index
  my $unroll_transition;

  my $last_frame_size = 0;

  for (my $i = 0 ; $i < scalar(@$source_file_list) ; $i++) {
#    print "i is $i\n";

    my $prefix = $Timelapse::SEQUENCE_IMAGE_PREFIX;

    my $filename = sprintf($prefix."%05d.tif",
			   $output_image_index+1); # XXX start at 1
    $output_image_index++;
    my $image_blender = ImageBlender->new("$new_dirname/$filename");
    push @$image_blender_list, $image_blender;

    if($i < $start_blend_index) {
      # here we should just pass the current image
      $image_blender->add("$source_dirname/$source_file_list->[$i]", 1);

    } else {
      # more complicated
      if ($i < $mid_blend_index) {

	my $start = $start_blend_index-1;

	if($i - $start > $max_blend_window_size) {
	  $start = $i - $max_blend_window_size;
	  $last_frame_size = $max_blend_window_size;
	} else {
	  $last_frame_size = $i - $start;
	}

	# XXX check max here

	my $transition = GaussianTransition->new($i - $start,
						 $lowest_value,
						 1);

	# we are between the begin and end
	for (my $j = $start ; $j < $i ; $j++) {
	  my $fuck = $j + 1;	# XXX WHY???
	  $image_blender->add("$source_dirname/$source_file_list->[$fuck]",
			      $transition->value_at_position($j-$start));
	}

      } elsif($i < $end_blend_index) {
	# here we are unrolling at the end

	unless (defined $unroll_transition) {
	  # how fast do we reduce the size of the blend window after mid_blend_index
	  $unroll_transition = GaussianTransition->new($end_blend_index - $mid_blend_index,
						       $last_frame_size,
						       1);
	}

	my $transition_idx = $i-$mid_blend_index;
	my $transition_amt = $unroll_transition->value_at_position($transition_idx);
	my $blend_size = int($transition_amt);
#	print "blend size $blend_size @ $transition_idx for transition_amt $transition_amt\n";
	$blend_size = 1 if($blend_size < 1);

#	print "for $i got last_frame_size $last_frame_size transition_amt $transition_amt blend_size $blend_size\n";

	my $start = $i - $blend_size;

	my $transition = GaussianTransition->new($i - $start,
						 $lowest_value,
						 1);

	for (my $j = $start ; $j < $i ; $j++) {
	  my $fuck = $j + 1;	# XXX WHY???
	  $image_blender->add("$source_dirname/$source_file_list->[$fuck]",
			      $transition->value_at_position($j-$start));

	}
      } else {
	$image_blender->add("$source_dirname/$source_file_list->[$i]", 1);
      }
    }
  }

  ImageBlender::logImageBlenderList($image_blender_list) if($should_log);

  if($should_run) {
    # then fork and do them in parallel
    Forker::run($image_blender_list, $max_children);

    return $new_dirname;
  }
}

1;

