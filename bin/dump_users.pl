#!/software/perl-5.8.6/bin/perl
  
  use strict;
  use lib $ENV{"ESTAR_PERL5LIB"};     

  use eSTAR::SOAP::User;
  use Storable qw(freeze thaw);

  my $db = new eSTAR::SOAP::User();
  my %list = $db->list_users();


  foreach my $key ( keys %list ) {
     print "Username: " . $key . ", Password: " . $list{$key} . "\n";
     
  }

  print "No users found in db.\n" unless %list;
 
  
  exit;
  
