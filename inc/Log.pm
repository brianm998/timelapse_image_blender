package Log;

require Exporter;

use Term::ANSIColor qw(:constants);

our @ISA = qw(Exporter);
our @EXPORT_OK = qw(timeLog logSystem);

$Term::ANSIColor::AUTORESET = 1;

sub timeLog {
  my $d = `date "+%r"`;
  chomp $d;
  print YELLOW, "      $d", RESET, " - ", @_, "\n";
}

sub logSystem {
  my ($cmd) = @_;
  my $d = `date "+%r"`;
  chomp $d;
  print YELLOW, "      $d", RESET, " - ", MAGENTA, "exec", RESET, ": ", BLUE "$cmd\n";
#  die "$!\n" if($ret != 0);

  return system($cmd);
}

return 1;



