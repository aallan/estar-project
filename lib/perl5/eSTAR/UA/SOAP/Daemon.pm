package eSTAR::UA::SOAP::Daemon;

use threads;
use threads::shared;

use strict;
use vars qw(@ISA);
use Data::Dumper;

# Based on SOAP::Transport::HTTP::Daemon::ThreadOnAccept, which in
# turn is a threaded implemetation of SOAP::Transport::HTTP::Daemon
use SOAP::Transport::HTTP::Daemon::ThreadOnAccept;

# Code based on WishList::Daemon.pm taken from "Programming Web
# Services with Perl" by Ray & Kulchenko.

@ISA = qw(SOAP::Transport::HTTP::Daemon::ThreadOnAccept);

# request() is the only method that needs overloading in order for
# this Daemon class to handle the authentication. All cookie headers
# on the incoming request get copied to a hash table local to the
# eSTAR::UA::Handler::SOAP package. The request is then passed on
# to the original version of this method.

sub request {
  my $self = shift;
  
  #use Data::Dumper;
  #print "eSTAR::UA::SOAP::Daemon\n";
  
  if ( my $request = $_[0] ) {         
    
    #print "\$request = " . Dumper ( $request ) . "\n";
    
    
    #print "Request = ";
    #print Dumper($request);
    #print Dumper($self);
    
    my @cookies = $request->headers()->header('cookie');

    #print "\@cookies = " . Dumper( @cookies ) . "\n";
    
    %eSTAR::UA::SOAP::Handler::COOKIES = ();
    for my $line (@cookies) {
       for ( split(/; /, $line)) {
          next unless /(.*?)=(.*)/;
          $eSTAR::UA::SOAP::Handler::COOKIES{$1} = $2;
       }   
    }
  }

  $self->SUPER::request(@_);
}

1;
