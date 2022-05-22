#!/usr/bin/perl

# This script transforms timelapse image sequences, blending some number of source frames
# into each output frame.
#
# Multiple blending methods are supported
#
# After blending the source image sequence into a new image sequence, a video is rendered
# and the new image sequence is removed if the render is successful.

use strict;
use File::Basename;
use Cwd;
use Getopt::Long qw(GetOptionsFromArray);

my $script_dir;	# figure out where this running script exists on disk
BEGIN { $script_dir = Cwd::realpath( File::Basename::dirname(__FILE__)) }

# add this dir to the include path
use lib "${script_dir}/inc";

# so we can use these custom modules
use Exiftool;
use Log qw(timeLog);
use Timelapse;
use ImageBlender;
use LinearBlender;
use GaussianBellCurveBlender;
use GaussianTrailBlender;
use GaussianTrailStreakBlender;
use MaxChildren;

# if we get past this validation, then all of our dependent services are present
# if not, then the user should be shown what's missing, and ideally how to install it
Timelapse::validate();
ImageBlender::validate();
Exiftool::validate();


# improvements:
#  - support more than tif
#  - better handle directories with files that are not images
#  - expose max child processes as parameter
#  - support re-processing, and skipping exising files
#    i.e. dir exists already keep processing, but skip what's there already
#  - add args, to support:
#    - handling multiple blends sequentially
#  - add ability to apply this process to video directly:
#    https://web.archive.org/web/20210621172103/https://trac.ffmpeg.org/wiki/Create%20a%20thumbnail%20image%20every%20X%20seconds%20of%20the%20video
#    - turn video into sequence of still images, process, and then re-encode

# list of all supported blenders
my @blenders =
  (
   LinearBlender->new(),
   GaussianBellCurveBlender->new(),
   GaussianTrailBlender->new(),
   GaussianTrailStreakBlender->new(),
  );

# map of name to blender instance
my $blenders = { };
foreach my $blender (@blenders) {
  $blenders->{$blender->{name}} = $blender;
}

my $logging_only = 0;
my $skip_video = 0;

use Sys::Info;
use Sys::Info::Constants qw( :device_cpu );
my %options;
my $cpu  = Sys::Info->new->device( CPU => %options );

# default to cpu count for max children
my $default_max_children = $cpu->count;

# get global opts from a different array so @ARGV stays virgin
my @pargv = @ARGV;
my $old_warn = $SIG{__WARN__};
$SIG{__WARN__} = sub { };	# supress warnings about other args
GetOptionsFromArray(\@pargv,
		    "info-only" => \$logging_only,
		    "no-video" => \$skip_video,
		    "max-children=i" => \$default_max_children);
$SIG{__WARN__} = $old_warn;

# this is the total number of child processes we will fork at once,
# the file below can be created and edited to have a single integer value
# this script will then dynamically adjust the max number of children it is using.
my $max_children = MaxChildren->new("/tmp/timelapse_image_blender_max_children.txt",
				    $default_max_children);

# figure out what blender we should use
my $blender = undef;
my $action = undef;

# pull off any global args before the action,
# check to see if any args are an action by using the blenders map
# this ends when we've either got a blender or run out of args.
while($blender == undef && scalar(@ARGV) > 0) {
  $action = shift;

  $blender = $blenders->{$action};
}

if (defined $blender) {
  # parse the remaining args, which are blender specific
  my $parse_error = $blender->parseArgs();
  unless(defined $parse_error) {
    # our blender has successfully parsed the command line args

    timeLog("running with ",$max_children->currentValue()," max children");
    $blender->{max_children} = $max_children;

    if ($logging_only) {
      # this just prints out how we would blend, without actually blending
      # useful for quickly testing what blend parameters might look good
      $blender->logBlendInfo();
    } else {
      # actually run the blend on the sequence
      $blender->blendSequence();
      # at this point the output sequence should exist
      unless ($skip_video) {
	if (my $video_name = $blender->renderVideo()) {
	  print "rendered video ",$blender->{video_filename},"\n";
	  $blender->deleteBelendedImageSequence();
	}
      }
    }
  } else {
    # missing required blender args
    my $usage = $blender->usage();
    print "error: $parse_error for blender ",$blender->{name},":\n";
    print $blender->description();
    print "\n$usage\n";
  }
} else {
  # no action arg on command line
  print "no defined blender for '$action'\n\n";
  usage();
}

sub usage() {
  print <<END
usage: $0 [ global args ] action [ action specific args ]

 global args:

   --info-only             - just print out how the images would blend with given settings
   --max-children value    - max number of children processes default is number of cpus
   --no-video              - don't render a video, don't remove the output image sequence

where action is one of:

END
;

  foreach my $blender (@blenders) {
    my $action = $blender->{name};
    my $desc = $blender->description();
    print " - $action:\n\n";
    print "$desc\n";
  }
}
