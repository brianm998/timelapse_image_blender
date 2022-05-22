package ImageBlender;

use strict;
use POSIX ":sys_wait_h";
use WeightedImage;
use TimelapseExiftool;
use Term::ANSIColor qw(:constants);

sub validate() {
  # we need convert (ImageMagick)

  die <<END
ERROR

ImageMagick is not installed

visit https://imagemagick.org

and install it to use this tool
END
    unless(system("which convert >/dev/null") == 0);
}

sub new {
  my ($class, $output_filename) = @_;
  my $self =
    {
     'output_filename', $output_filename,
     'image_list', [],
    };

  return bless $self, $class;
}

sub numberOfImages() {
  my ($self) = @_;

  my $ret = scalar(@{$self->{image_list}});
  #print "fuck '$ret'\n";
  return $ret;
}

sub nextImage() {
  my ($self) = @_;

  return shift @{$self->{image_list}};
}

sub setImageList() {
  my ($self, $image_list) = @_;

  foreach my $image (@$image_list) {
    $self->addImage($image);
  }
}

# adds a weighted image to the list
sub addImage() {
  my($self, $image) = @_;

  unshift @{$self->{image_list}}, $image;
}

# adds a weighted image to the list
sub add() {
  my($self, $filename, $weight) = @_;

  $self->addImage(WeightedImage->new($filename, $weight));
}

sub execute() {
  my ($self) = @_;

  $self->blend_images();
}

# destructive method which renders to the output file with a single shell command
sub blend_images() {
  my ($self) = @_;

  my $total_weight = 0;
  foreach my $image (@{$self->{image_list}}) {
    $total_weight += $image->{weight};
  }

  my @FF = map { $_->description($total_weight); } @{$self->{image_list}};

  TimelapseExiftool::timeLog(
      MAGENTA, "blending ", BLUE, ,$self->numberOfImages(),
      " images:\n\t",RESET, join("\n\t", @FF),MAGENTA,
      "\ninto\n\t", BLUE,$self->{output_filename}, "\n", RESET
  );

  if($self->numberOfImages() == 1) {
    # if we are only blending one image, simply copy it and be done
    # source image and dest should be on same filesystem, so ln should be fast
    my $image = $self->nextImage();
    ln_or_cp($image->{filename}, $self->{output_filename});
    return;
  }

  # start to assemble the convert command line
  my $cmd = "convert ";

  # grab the first two images, removing them from the list
  my $image_1 = $self->nextImage();
  my $image_2 = $self->nextImage();

  # and their weights
  my $weight_1 = $image_1->{weight};
  my $weight_2 = $image_2->{weight};

  # calculate blend percentages
  my $percentage_1 = $weight_1 / ($weight_1 + $weight_2) * 100;
  my $percentage_2 = $weight_2 / ($weight_1 + $weight_2) * 100;

  # the convert command expects the first two images like this
  $cmd .= $image_1->{filename};
  $cmd .= " ";
  $cmd .= $image_2->{filename};
  $cmd .= " -compose blend -define compose:args=$percentage_1"."x"."$percentage_2  -composite ";

  my $previous_weight = $weight_1+$weight_2;

  # any subsequent images need to be added to the command line individually
  while($self->numberOfImages() > 0) {
    # grab the next image, removing it from the list
    my $next_image = $self->nextImage();

    # and its weight
    my $next_weight = $next_image->{weight};

    # calculate blend percentages
    my $next_image_blend_percentage = $next_weight / ($next_weight + $previous_weight) * 100;
    my $previous_blend_percentage = $previous_weight / ($next_weight + $previous_weight) * 100;

    $cmd .= $next_image->{filename};
    $cmd .= " -compose blend -define compose:args=";
    $cmd .= $next_image_blend_percentage."x".$previous_blend_percentage;
    $cmd .= " -composite ";

    $previous_weight += $next_weight;
  }

  $cmd .= $self->{output_filename};

  TimelapseExiftool::timeLog("starting render of ", $self->{output_filename});

  my $start_time = time;

  if(system($cmd) != 0) {	# don't log this directly, it can get ginormous
      warn "render of "+$self->{output_filename}+" failed: $!\n";
      die "failed: $!\n";
  }

  my $end_time = time;

  TimelapseExiftool::timeLog("render of ", $self->{output_filename}, " complete, took ",($end_time-$start_time), " seconds");
}

# try to make a hard link instead of copying
sub ln_or_cp() {
  my($source_file, $dest_file) = @_;

  # if both are on same filesystem, ln will work, and is a fast metadata update.
  unless(TimelapseExiftool::logSystem("ln $source_file $dest_file") == 0) {
    # if ln fails, then just go ahead and copy it.  Slower, but should work.
    return TimelapseExiftool::logSystem("cp $source_file $dest_file")
  }

  return 0;
}

# takes a list of jobs to run
# forks per job up to $max_children to speed things up
sub run_job_list($$) {
  my ($job_list, $max_children) = @_;

  my $idx = 0;			# index into $job_list

  my @child_pids = ();

  local $SIG{CHLD} = "IGNORE";
  my $pid;

  # process each set of images to blend
  # logging in the following loop is considered harmful to performance
  while($idx < scalar(@$job_list)) {
    # attempt to invoke a unix process fork to process each frame

    my $current_max = $max_children->currentValue();

    if (!defined($pid = fork())) {
      # fork returned undef, so unsuccessful
      die "Cannot fork a child: $!";
    } elsif ($pid == 0) {
      # forked to child here
      # grab the list of images to blend
      my $image_blender = $job_list->[$idx];
      $image_blender->execute();
      # now $output_filename should exist
      exit;			# child is done
    } else {
      # parent code here

      # keep track of the pid we just forked
      push @child_pids, $pid;

      # next child will merge images for the next output frame
      $idx++;

      # check to see if we have too many children
      while (scalar(@child_pids) >= $max_children->currentValue()) {
	my $should_sleep = 1;
	for my $child_pid (@child_pids) {
	  my $ret = waitpid($child_pid, WNOHANG);
	  if ($ret != 0) {
	    # $child_pid is no longer running

	    # remove $child_pid from @child_pids

	    my $child_pid_idx = undef;
	    for (my $i = 0 ; $i < scalar(@child_pids) ; $i++) {
	      if ($child_pids[$i] == $child_pid) {
		$child_pid_idx = $i;
		last;
	      }
	    }
	    if (defined $child_pid_idx) {
	      # remove the finished pid from the list
	      splice(@child_pids, $child_pid_idx, 1);
	      # don't sleep, as @child_pids is now below $max_children
	      $should_sleep = 0;
	    } else {
	      die "shit\n";	# XXX un-shit this
	    }
	  }
	}
	if($should_sleep) {
	  # here all of our children are working, and we're at max
	  sleep 1;
	}
      }
    }
  }

  TimelapseExiftool::timeLog("all children started");

  # here we've forked separate processes to blend each output frame,
  # however it's likely that they're not all done yet

  # check here to make sure our children are done
  while (scalar(@child_pids) > 0) {
    TimelapseExiftool::timeLog("still have ",scalar(@child_pids)," children running");
    for my $child_pid (@child_pids) {
      my $ret = waitpid($child_pid, 0);
      if($ret != 0) {
	# XXX this could be a function, same code is above
	my $child_pid_idx = undef;
	for (my $i = 0 ; $i < scalar(@child_pids) ; $i++) {
	  if ($child_pids[$i] == $child_pid) {
	    $child_pid_idx = $i;
	    last;
	  }
	}
	if (defined $child_pid_idx) {
	  splice(@child_pids, $child_pid_idx, 1);
	}
      }
    }
  }
}

sub logImageBlenderList($) {
  my ($image_blender_list) = @_;

  foreach my $image_blender (@$image_blender_list) {

    my $total_weight = 0;
    foreach my $image (@{$image_blender->{image_list}}) {
      $total_weight += $image->{weight};
    }

    my @FF = map { $_->description($total_weight); } @{$image_blender->{image_list}};

    print "blending ",$image_blender->numberOfImages(),
			       " images:\n\t", join("\n\t", @FF),
			       "\ninto\n\t", $image_blender->{output_filename}, "\n", 
			      ;

  }
}

1;


