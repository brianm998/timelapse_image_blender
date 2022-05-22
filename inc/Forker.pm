package Forker;

use strict;
use POSIX ":sys_wait_h";
use Log qw(logSystem timeLog);
use Term::ANSIColor qw(:constants);

# takes a list of jobs to run
# forks per job up to $max_children to speed things up
sub run($$) {
  my ($job_list,		# array ref of job objects that respond to execute()
      $max_children) = @_;	# integer number of max children processes to fork

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
      # grab the next job to run
      my $job = $job_list->[$idx];
      $job->execute();
      # now job is finished, and so is child process
      exit;			# exit child
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

  timeLog("all children started");

  # here we've forked separate processes to blend each output frame,
  # however it's likely that they're not all done yet

  # check here to make sure our children are done
  while (scalar(@child_pids) > 0) {
    timeLog("still have ",scalar(@child_pids)," children running");
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


