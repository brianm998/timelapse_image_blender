package TimelapseExiftool;

use Term::ANSIColor qw(:constants);
use Text::CSV qw( csv );

$Term::ANSIColor::AUTORESET = 1;

sub validate() {
  # we need exiftool

  die <<END
ERROR

exiftool is not installed

visit https://exiftool.org

and install it to use this tool
END
    unless(system("which exiftool >/dev/null") == 0);
}

sub new {
  my ($class) = @_;

  my $base = { };

  return bless $base, $class;
}

# returns a basic map of the exiftool output for the given filename
sub run_exiftool() {
  my ($self, $filename) = @_;
  my $ret = {};

  #  open my $fh, "exiftool -csv $filename |";

  my $csv = Text::CSV->new ({ binary => 1, auto_diag => 1 });
  open my $fh, "exiftool -csv $filename |" or die $!;

  # first row is keys
  my $row1 = $csv->getline ($fh);
  # second row is values
  my $row2 = $csv->getline ($fh);

  # no other rows
  
  my $exif_data = {};

  for(my $i = 0 ; $i < scalar @$row1 ; $i++) {
    $exif_data->{$row1->[$i]} = $row2->[$i];
  }

  close $fh;

  return $exif_data;
}


return 1;



