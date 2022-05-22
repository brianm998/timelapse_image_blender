package GaussianBellCurve;

use strict;

# a gaussian bell curve
sub new {
  my ($class,
      $window_size,		# full size of the curve (one end to the other)
      $highest_value,		# value at the top of the curve
      $lowest_value)		# lowest value at the beginning of the curve
    = @_;

  my $a = $highest_value;
  my $b = int $window_size/2;	# middle of curve
  my $c = reverse_gaussian_for_c($lowest_value, $a, $b, 0);

  my $self =
    {
     'a', $a,
     'b', $b,
     'c', $c,
     'name', "$window_size-way-hi-$highest_value-lo-$lowest_value",
     };

  return bless $self, $class;
}

# returns the value at $position
# position 0  == $lowest_value
# position $window_size/2 == $highest_value
# position $window_size-1 == $lowest_value
sub value_at_position() {
  my ($self, $position) = @_;

  my $x = $position;
  my $a = $self->{a};
  my $b = $self->{b};
  my $c = $self->{c};

  return $a * exp (-($x-$b)*($x-$b)/(2*$c*$c));
}

# runs gaussian function in reverse to get the C value out from other params
sub reverse_gaussian_for_c() {
  my ($o,			# desired output of gaussian function
      $a,			# gaussian a param
      $b,			# gaussian b param
      $x) = @_;			# index of sequence

  return sqrt(-($x-$b)*($x-$b)/(2*log($o/$a)));
}
1;
