package GaussianTransition;

use strict;

# a gaussian bell transition from one value to another
# this is not a full bell curve, but just one half of it,
# either the beginning or the end, depending upon the values given.
sub new {
  my ($class,
      $length,	                # number of elements in the transition
      $start_value,		# value at start
      $end_value)		# value at end
    = @_;

  my $highest_value = 0;

  die "start and end values cannot be zero\n" if($end_value == 0 || $start_value == 0);

  #print "length $length\n";

  my $b = $length-1;
  my $c = 0;
  if($end_value < $start_value) {
    #print "a\n";
    $highest_value = $start_value;
    $b = 0;
    $c = reverse_gaussian_for_c($end_value, $highest_value, $b, $length-1);
  } else {
    #print "b\n";
    $highest_value = $end_value;
    $c = reverse_gaussian_for_c($start_value, $highest_value, $b, 0);
  }

  my $a = $highest_value;

  my $self =
    {
     'a', $a,
     'b', $b,
     'c', $c,
     'name', "$length-way-start-$start_value-end-$end_value",
     };

  return bless $self, $class;
}

# returns the value at $position
# position 0  == $lowest_value
# position $window_size-1 == $highest_value
sub value_at_position() {
  my ($self, $position) = @_;

  my $x = $position;
  my $a = $self->{a};
  my $b = $self->{b};
  my $c = $self->{c};

  return 1 if($c == 0);		# math error

  #print "x $x a $a b $b c $c\n";

  return $a * exp (-($x-$b)*($x-$b)/(2*$c*$c));
}

# runs gaussian function in reverse to get the C value out from other params
sub reverse_gaussian_for_c() {
  my ($o,			# desired output of gaussian function
      $a,			# gaussian a param
      $b,			# gaussian b param
      $x) = @_;			# index of sequence

  #print "o $o a $a b $b x $x\n";

  return sqrt(-($x-$b)*($x-$b)/(2*log($o/$a)));
}
1;
