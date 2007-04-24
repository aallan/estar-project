#!/usr/bin/perl

use strict;
use warnings;

use File::Spec;
use Carp;
use Getopt::Long;
use Data::Dumper;

use XMLRPC::Lite;

# C O M M A N D   L I N E --------------------------------------------------

# Grab the username and password from the command line
unless( scalar @ARGV >= 2 ) {
  croak( "USAGE: $0 -user username -pass password [-community community]" );
}
my ( $user, $pass, $community );
my $option_status = GetOptions( 
       "user=s" => \$user, "pass=s" => \$pass, "community=s" => \$community );  

unless ( defined $user && defined $pass ) {
   croak( "You must enter a valid username and password" );
} 

# Assume a community
unless ( defined $community ) {
   $community = "org.astrogrid.workshop";
}   

# R P C -------------------------------------------------------------------

# Grab an RPC endpoint for the ACR
my $file = File::Spec->catfile( "$ENV{HOME}", ".astrogrid-desktop" );
croak( "Unable to open file $file" ) unless open(PREFIX, "<$file" );

my $prefix = <PREFIX>;
close( PREFIX );
chomp( $prefix );

my $endpoint = $prefix . "xmlrpc";

my $rpc = new XMLRPC::Lite();
$rpc->proxy($endpoint);

# L O G I N ---------------------------------------------------------------
 
# Check to see whether we're already logged into AstroGrid
my $login;
eval { $login = $rpc->call( 'astrogrid.community.isLoggedIn' ); };
if( $@ ) {
   croak( "Unable to check login status: $@" );                      
}

# If we're not logged in, then login...
unless ( $login->result() ) {
  print "Logging into Astrogrid as '". $user ."' with password '".$pass."'...\n";
  
  my $do_login;
  eval { $do_login = $rpc->call( 'astrogrid.community.login',
                                 $user, $pass, $community ); };
  # Check for exceptions
  if( $@ ) {
   croak( "Failed to login: $@" );                      
  } 
  
  # Check for faults
  if( $do_login->faultcode() ) {
     croak( "Failed to login: " . $do_login->faultstring() );
  } 
}

# Check that the login call really has worked
eval{ $login = $rpc->call( 'astrogrid.community.isLoggedIn' ); };
if( $@ ) {
   croak( "Unable to check login status: $@" );
} else {
   if( $login->result() ) {
      print "Successfully logged into AstroGrid.\n";
   } else {
      croak( "Login unsucessful, exiting..." );
   }         
}

# M A I N   B L O C K -----------------------------------------------------

# GetHome()

my $result;
eval{ $result = $rpc->call( 'astrogrid.myspace.getHome' ); };
if( $@ ) {
   croak( "Unable to get home directory: $@" );
}   
unless( $result->fault() ) {
   print "Home Directory: " . $result->result() . "\n";
} else {
   croak( "Error:: ". $result->faultstring );
}

# C L E A N   U P ---------------------------------------------------------

# Check that the login call really has worked
eval{ $login = $rpc->call( 'astrogrid.community.logout' ); };

# Check for exceptions
if( $@ ) {
   croak( "Unable to logout: $@" );
}

# Check for faults
if( $login->faultcode() ) {
  croak( "Unable to login: " . $login->faultstring() );
} 

print "Successfully logged out of AstroGrid.\n";  
exit;
