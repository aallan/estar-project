package eSTAR::Process;

=head1 NAME

eSTAR::Process - wrapper object to hold process related data

=head1 SYNOPSIS

  use eSTAR::Process
  
  $process = new eSTAR::Process( $process_name );
  $process = eSTAR::Process::get_reference();
  
  $process->set_process( $process_name )
  $process->get_process()
  
=head1 DESCRIPTION

This module contains simpel wrapped routines to hold information
concerning the current process. Currently only holds the process
name for use by eSTAR::Util. Th.is is a single instance object

=cut

use strict;
use warnings;

require Exporter;

use vars qw/$VERSION @EXPORT @ISA/;

@ISA = qw/Exporter/;
@EXPORT = qw/set_process get_process get_reference/;

'$Revision: 1.1 $ ' =~ /.*:\s(.*)\s\$/ && ($VERSION = $1);

my $SINGLETON;

sub new {
   return $SINGLETON if defined $SINGLETON;

   my $proto = shift;
   my $class = ref($proto) || $proto;   
   $SINGLETON = bless { PROCESS => undef }, $class;
   
   $SINGLETON->set_process( @_ );
   return $SINGLETON;
}

sub get_reference {
  return $SINGLETON if defined $SINGLETON;
  return undef;
}

sub set_process {
   my $self = shift;
   $self->{PROCESS} = shift;   
}

sub get_process {
   my $self = shift;
   return $self->{PROCESS};
}   

=back

=head1 REVISION

$Id: Process.pm,v 1.1 2004/02/20 00:42:29 aa Exp $

=head1 AUTHORS

Alasdair Allan E<lt>aa@astro.ex.ac.ukE<gt>

=head1 COPYRIGHT

Copyright (C) 2003 Particle Physics and Astronomy Research
Council. All Rights Reserved.

=cut

1;
