package eSTAR::SOAP::User;

use strict;
use vars qw($DBNAME);
use subs qw(import get_user write_user name dbconnect);

use DB_File 1.806;
use Storable qw(freeze thaw);
use Config::User;
use File::Spec;

sub import {
  my ($proto, %args ) = @_;
  
  # check for existance of DB user file
  my $dbfile = 
    File::Spec->catfile(Config::User->Home(), '.estar', 'users.db' );
      
  # only $args{database} is currently parsed
  $DBNAME = $args{database} || $dbfile;
  
}

sub new {
   my ($class, %args ) = @_;

   # build a blank hash and fill it from the arguements
   my %hash;
   %hash = ( name => "", passwd => "" );

   # copy arguements to blessed object
   $hash{passwd} = $args{passwd};
   $hash{name} = $args{name};
   
   bless \%hash, $class;
   
}

sub get_user {
   my ($self, $user) = @_;
   
   my ($db, $val);
   $db = dbconnect();
   
   return undef if ($db->get($user, $val));
   $val = thaw $val;
   %$self = %$val;
   
   return $self;
}

sub write_user {
   my $self = $_[0];
   
   return undef unless $self->{name};
   my $db = dbconnect();
   
   # pass freeze() a hashref to a COPY of $self, unblessed
   return undef if ($db->put($self->{name}, freeze({ %$self})));
   
   return $self;
}

sub name { 
   return $_[0]->{name}; 
}

sub passwd {
   my ( $self, $newpass ) = @_;
    
   $self->{passwd} = $newpass if $newpass;
   return $self->{passwd};
}

sub list_users {
   my $self = shift;
   
   # conenct to DB
   my $db = dbconnect();
   
   # iterate through the btree using seq
   # and print each key/value pair.
   my $key = 0;
   my $value = 0;
   my %list;
   my $status;
   for ( $status = $db->seq($key, $value, R_FIRST) ; $status == 0 ;
         $status = $db->seq($key, $value, R_NEXT) ) {  
  
      # push to returned hash
      my $thaw = thaw $value;
      my %hash = %$thaw;
      $list{ $key} = $hash{"passwd"};
   } 

   return %list;
   

}

sub dbconnect {

    # tie the DB to a hash
    my %hash;
    my $db = tie %hash, 'DB_File', $DBNAME;
    
    # return a copy of the DB object
    return $db;
}

1;                 
