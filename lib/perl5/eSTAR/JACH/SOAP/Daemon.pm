package eSTAR::JACH::SOAP::Daemon;

use threads;
use threads::shared;

use strict;
use vars qw(@ISA);

use SOAP::Transport::HTTP::Daemon::Threaded;

# Code based on WishList::Daemon.pm taken from "Programming Web
# Sercies with Perl" by Ray & Kulchenko.

@ISA = qw(SOAP::Transport::HTTP::Daemon::Threaded);

# request() is the only method that needs overloading in order for
# this Daemon class to handle the authentication. All cookie headers
# on the incoming request get copied to a hash table local to the
# eSTAR::JACH::Handler::SOAP package. The request is then passed on
# to the original version of this method.

sub request {
  my $self = shift;
  
  #use Data::Dumper;
  #print "eSTAR::WFCAM::SOAP::Daemon\n";
    
  if ( my $request = $_[0] ) {         
    
    #print "\$request = " . Dumper ( $request ) . "\n";
    
    my @cookies = $request->headers()->header('cookie');
 
    #print "\@cookies = " . Dumper( @cookies ) . "\n";
    
    %eSTAR::JACH::SOAP::Handler::COOKIES = ();
    for my $line (@cookies) {
       for ( split(/; /, $line)) {
          next unless /(.*?)=(.*)/;
          $eSTAR::JACH::SOAP::Handler::COOKIES{$1} = $2;
       }   
    }
  }

  $self->SUPER::request(@_);
}

1;
