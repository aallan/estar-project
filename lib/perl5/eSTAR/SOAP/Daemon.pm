package eSTAR::SOAP::Daemon;

use threads;
use threads::shared;

use strict;
use vars qw(@ISA $module);

# Based on SOAP::Transport::HTTP::Daemon::ThreadOnAccept, which in
# turn is a threaded implemetation of SOAP::Transport::HTTP::Daemon
use SOAP::Transport::HTTP::Daemon::ForkAfterProcessing;

# Code based on WishList::Daemon.pm taken from "Programming Web
# Services with Perl" by Ray & Kulchenko.

@ISA = qw(SOAP::Transport::HTTP::Daemon::ForkAfterProcessing);

# overload new() so that we can pass in the name of the SOAP handler
# that we should be using to deal with incoming SOAP requests.

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  $module = shift;
  
  my %args = @_;

  if (exists $args{"Module"} ) {
     $module = $args{"Module"};
     delete $args{"Module"};
  }   
  $class->SUPER::new( %args );
}  

# request() is the only method that needs overloading in order for
# this Daemon class to handle the authentication. All cookie headers
# on the incoming request get copied to a hash table local to the
# eSTAR::*::SOAP::Handler packages. The request is then passed on
# to the original version of this method.

sub request {
  my $self = shift;
  
  #use Data::Dumper;
  #print "eSTAR::SOAP::Daemon\n";
  
  if ( my $request = $_[0] ) {         
    
    #print "\$request = " . Dumper ( $request ) . "\n";
    
    my @cookies = $request->headers()->header('cookie');

    #print "\@cookies = " . Dumper( @cookies ) . "\n";
    
    %eSTAR::$module::SOAP::Handler::COOKIES = ();
    for my $line (@cookies) {
       for ( split(/; /, $line)) {
          next unless /(.*?)=(.*)/;
          $eSTAR::$module::SOAP::Handler::COOKIES{$1} = $2;
       }   
    }
  }

  $self->SUPER::request(@_);
}

1;
