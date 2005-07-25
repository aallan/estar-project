# SOAP layer ontop of eSTAR::NAN::Handler
package eSTAR::RAPTOR::SOAP::Handler;

use strict;
use vars qw( @ISA %COOKIES );

use SOAP::Lite;
use eSTAR::RAPTOR::Handler;

@ISA = qw(eSTAR::RAPTOR::Handler);

BEGIN {
  no strict 'refs';
  
  # This block creates local versions of the methods in the Handler
  # class. The local versions catch errors that would otherwise be
  # simple text, and turn them into SOAP::Fault objects.
  
  for my $method qw(ping handle_rtml) {
     eval "sub $method";
     *$method = sub {
        my $self = shift->new();
                
        # if we don't have a new object, die and report and error
        die SOAP::Fault
            ->faultcode('Server.RequestError')
            ->faultstring('Could not get object')
        unless $self;
                
        my $smethod = "SUPER::$method";
        my $res = $self->$smethod(@_);
        
        # die if we have a fault in the original method
        die SOAP::Fault
            ->faultcode('Server.ExecError')
            ->faultstring("Execution Error: $res")
        unless ref($res);
        
        $res;
     };
     
  }
}

1;

# the class constructor. It is designed to be called by each invocation
# of each other method. As such, it returns the first arguement immediately
# if it is already an object of the class. This lets users of the class
# rely on constructs such as cookie-based authentication, where each
# request calls for a new object instance

sub new {            
   my $class = shift;
   return $class if ref($class);
   
   my $log = shift;
   
   my $self;
   # if there are no arguements, but available cookies, 
   # then that is the signal to use the cookies
   if( (! @_) and (keys %COOKIES) ) {
     
     # start by getting the basic, bare object
     $self = $class->SUPER::new();
     
     # then call set_user. It will die with a SOAP::Fault on any error
     $self->set_user();
   
   } else {
   
     $self = $class->SUPER::new(@_);
     
   }
   
   $self;
}

# this derived version of set_user() hands off to the parent class if any
# arguements are passed. If none are, it looks for cookies to provide
# authentication. The user name is extracted from the cookie, and the
# "user" and "cookie" arguements are passed to the parent class set_user
# method with these values.

sub set_user {
   my $self = shift->new();
   my %args = @_;
   
   return $self->SUPER::set_user(%args) if (%args);
   
   my $user;
   my $cookie = $COOKIES{user};
   return $self unless $cookie;
   
   ( $user = $cookie ) =~ s/%([0-9a-f]{2})/chr(hex($1))/ge;
   $user =~ s/%([0-9a-f]{2})/chr(hex($1))/ge;
   $user =~ s/::.*//;
   
   my $res = $self->SUPER::set_user( user => $user, cookie => $cookie );
   
   die SOAP::Fault
        ->faultcode('Server.AuthError')
        ->faultstring("Authorisation failed: $res")
   unless ref($res);
   
   $self;
}             
                
