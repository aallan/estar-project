#!/home/perl/bin/perl
  
  use strict;
  use lib $ENV{"ESTAR_PERL5LIB"};     

  use eSTAR::SOAP::User;

  die "USAGE: $0 username password\n" unless ( scalar @ARGV == 2 );
  my $user = $ARGV[0];
  my $password = $ARGV[1];
  
  
  print "user = $user, password = $password\n";
  my $db = new eSTAR::SOAP::User(name => $user, passwd => $password);

  use Data::Dumper;
  print Dumper($db);


  $db->write_user();

  exit;
  
