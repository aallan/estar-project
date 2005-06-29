package Config::Simple;

# $Id: Simple.pm,v 1.1 2005/06/29 00:14:20 aa Exp $

use strict;
# uncomment the following line while debugging. Otherwise,
# it's too slow for production environment
#use diagnostics;
use Carp;
use Fcntl qw(:DEFAULT :flock);
use Text::ParseWords 'parse_line';
use vars qw($VERSION $DEFAULTNS $LC $USEQQ $errstr);
use AutoLoader 'AUTOLOAD';


$VERSION   = '4.58';
$DEFAULTNS = 'default';

sub import {
    my $class = shift;
    for ( @_ ) {
        if ( $_ eq '-lc'      ) { $LC = 1;    next; }
        if ( $_ eq '-strict'  ) { $USEQQ = 1; next; }
    }
}



# delimiter used by Text::ParseWords::parse_line()
sub READ_DELIM () { return '\s*,\s*' }
# delimiter used by as_string()
sub WRITE_DELIM() { return ', '      }
sub DEBUG      () { 0 }


sub new {
  my $class = shift;
  $class = ref($class) || $class;

  my $self = {
    _FILE_NAME      => undef,   # holds the name of the read configuration file
    _STACK          => [],      # currently not implemented
    _DATA           => {},      # actual key/value pairs are stored in _DATA
    _SYNTAX         => undef,   # holds the syntax of the read cfg file
    _SUB_SYNTAX     => undef,   # holds the sub-syntax (like for simplified ini)
    _ARGS           => {},      # holds all key/values passed to new()
    _OO_INTERFACE   => 1,       # currently not implemented
    _IS_MODIFIED    => 0,       # to prevent writing file back if they were not modified
  };
  bless ($self, $class);
  $self->_init(@_) or return;
  return $self;
}




sub DESTROY {
  my $self = shift;
  
  # if it was an auto save mode, write the changes
  # back only if the values have been modified.
  if ( $self->autosave() && $self->_is_modified() ) {
    $self->write();
  }
}




# initialize the object
sub _init {
  my $self = shift;

  if ( @_ == 1 ) {
    return $self->read($_[0]);
  } elsif ( @_ % 2 ) {
    croak "new(): Illegal arguments detected";
  } else {
    $self->{_ARGS} = { @_ };
  }
  # if syntax was given, call syntax()
  if ( exists $self->{_ARGS}->{syntax} ) {
    $self->syntax($self->{_ARGS}->{syntax});
  }
  # if autosave was set, call autosave
  if ( exists $self->{_ARGS}->{autosave} ) {
    $self->autosave($self->{_ARGS}->{autosave});
  }
  # If filename was passed, call read()
  if ( exists ($self->{_ARGS}->{filename}) ) {
    return $self->read( $self->{_ARGS}->{filename} );
  }  
  return 1;
}



sub _is_modified {
  my ($self, $bool) = @_;

  if ( defined $bool ) {
    $self->{_IS_MODIFIED} = $bool;
  }
  return $self->{_IS_MODIFIED};
}



sub autosave {
  my ($self, $bool) = @_;

  if ( defined $bool ) {
    $self->{_ARGS}->{autosave} = $bool;
  }
  return $self->{_ARGS}->{autosave};
}


sub syntax {
  my ($self, $syntax) = @_;  

  if ( defined $syntax ) {
    $self->{_SYNTAX} = $syntax;
  }  
  return $self->{_SYNTAX};
}


# takes a filename or a file handle and returns a filehandle
sub _get_file {
  my ($self, $arg, $mode) = @_;  
  
  unless ( defined $arg ) {
    croak "_get_file(): filename is missing";
  }
  if ( ref($arg) && (ref($arg) eq 'GLOB') ) {
    return ($arg, 0);
  }
  unless ( defined $mode ) {
      $mode = O_RDONLY;
  }
  
  my $handle;
  unless ( sysopen($handle, $arg, $mode) ) {
    unless ( sysopen($handle, $arg, O_RDWR|O_CREAT ) ) {
       $self->error("couldn't open $arg: $!");
       print "Error: couldn't open $arg: $!\n";
       return undef;
    }   
  }
  
  seek $handle, 0, 0;
  my $string;  
  {
      undef $/;
      $string = <$handle>;
  };    
  $self->close( $handle );
  
  my @file = split "\n", $string;
    
  return (@file);
}



sub read {
  my ($self, $file) = @_;
  
  unless ( defined $file ) {
    croak "Usage: OBJ->read(\$file_name)";
  }  
  
  $self->{_FILE_NAME}   = $file;
  
  my @file
     = $self->_get_file($file, O_RDONLY) or return undef;
   
  #print "\@file\n\n" . Dumper( @file ) . "\n\n"; 
   
    
  $self->{_SYNTAX} = $self->guess_syntax( @file ) or return undef;

  # call respective parsers

  if ( $self->{_SYNTAX} eq 'ini' ) {
        $self->{_DATA} = $self->parse_ini_file( @file );
  } elsif ( $self->{_SYNTAX} eq 'simple' ) {
        $self->{_DATA} = $self->parse_cfg_file( @file );
  } elsif ( $self->{_SYNTAX} eq 'http' ) {
        $self->{_DATA} = $self->parse_http_file( @file );
  }
  

    if ( $self->{_DATA} ) {
        return $self->{_DATA};
    }

  die "Something went wrong. No supported configuration file syntax found";
}


sub close {
  my $self = shift;
  my $fh = shift;
  unless ( CORE::close($fh) ) {
    $self->error("couldn't close the file: $!");
    return undef;
  }
  return 1;
}





# tries to guess the syntax of the configuration file.
# returns 'ini', 'simple' or 'http'.
sub guess_syntax {
  my $self = shift;
  my @lines = @_;
  
  my ($syntax, $sub_syntax);
  foreach my $i ( 0 ... $#lines ) {
  
    $_ = $lines[$i];
    #print "guess_syntax : $_\n";
    
    # skipping empty lines and comments. They don't tell much anyway
    /^(\n|\#|;)/ and next;

    # If there's no alpha-numeric value in this line, ignore it
    /\w/ or next;

    # trim $/
    chomp();

    # If there's a block, it is an ini syntax
    /^\s*\[\s*[^\]]+\s*\]\s*$/  and $syntax = 'ini', last;

    # If we can read key/value pairs separated by '=', it still
    # is an ini syntax with a default block assumed
    /^\s*[^=]+\s*=\s*.*\s*$/    and $syntax = 'ini', $self->{_SUB_SYNTAX} = 'simple-ini', last;

    # If we can read key/value pairs separated by ':', it is an
    # http syntax
    /^\s*[\w-]+\s*:\s*.*\s*$/   and $syntax = 'http', last;

    # If we can read key/value pairs separated by just whites,
    # it is a simple syntax.
    /^\s*[\w-]+\s+.*$/          and $syntax = 'simple', last;    
  }

  
  if ( $syntax ) {
    return $syntax;
  }

  $self->error("Couldn't identify the syntax used, guessing 'ini'");
  return 'ini';

}





sub parse_ini_file {
  my $class = shift;
  my @lines = @_;

  my $bn = $DEFAULTNS;
  my %data = ();
  foreach my $i ( 0 ... $#lines ) {
  
    my $line = $lines[$i];
    #print "parse_ini_file : $line\n";
    # skipping comments and empty lines:

    $line =~ /^\s*(\n|\#|;)/  and next;
    $line =~ /\S/          or  next;

    chomp $line;
    
    $line =~ s/^\s+//g;
    $line =~ s/\s+$//g;
    
    # parsing the block name:
    $line =~ /^\s*\[\s*([^\]]+)\s*\]$/       and $bn = lcase($1), next;
    # parsing key/value pairs
    $line =~ /^\s*([^=]*\w)\s*=\s*(.*)\s*$/  and $data{$bn}->{lcase($1)}=[parse_line(READ_DELIM, 0, $2)], next;
    # if we came this far, the syntax couldn't be validated:
    $errstr = "syntax error on line $. '$line'";
    return undef;    
  }
  
  return \%data;
}


sub lcase {
  my $str = shift;
  $LC or return $str;
  return lc($str);
}




sub parse_cfg_file {
  my $class = shift;
  my @lines = @_;

  my %data = ();
  my $line;
  foreach my $i ( 0 ... $#lines ) {
  
    $line = $lines[$i];
    #print "parse_cfg_file : $line\n";

    # skipping comments and empty lines:
    $line =~ /^(\n|\#)/  and next;
    $line =~ /\S/        or  next;    
    chomp $line;
    $line =~ s/^\s+//g;
    $line =~ s/\s+$//g;
    # parsing key/value pairs
    $line =~ /^\s*([\w-]+)\s+(.*)\s*$/ and $data{lcase($1)}=[parse_line(READ_DELIM, 0, $2)], next;
    # if we came this far, the syntax couldn't be validated:
    $errstr = "syntax error on line $.: '$line'";
    return undef;
  }
  
  return \%data;
}



sub parse_http_file {
  my $class= shift;
  my @lines = @_;

  my %data = ();
  foreach my $i ( 0 ... $#lines ) {
  
    my $line = $lines[$i];
    #print "parse_http_file : $line\n";
    
    # skipping comments and empty lines:
    $line =~ /^(\n|\#)/  and next;
    $line =~ /\S/        or  next;
    # stripping $/:
    chomp $line;
    $line =~ s/^\s+//g;
    $line =~ s/\s+$//g;
    # parsing key/value pairs:
    $line =~ /^\s*([\w-]+)\s*:\s*(.*)$/  and $data{lcase($1)}=[parse_line(READ_DELIM, 0, $2)], next;
    # if we came this far, the syntax couldn't be validated:
    $errstr = "syntax error on line $.: '$line'";
    return undef;
  }

  return \%data;
}


sub param {
  my $self = shift;

  # If called with no arguments, return all the
  # possible keys
  unless ( @_ ) {
    my $vars = $self->vars();
    return keys %$vars;
  }
  # if called with a single argument, return the value
  # matching this key
  if ( @_ == 1) {
    return $self->get_param(@_);    
  }
  # if we come this far, we were called with multiple
  # arguments. Go figure!
  my $args = {
    '-name',   undef,
    '-value',  undef,
    '-values', undef,
    '-block',  undef,
    @_
  };
  if ( defined $args->{'-name'} && (defined($args->{'-value'}) || defined($args->{'-values'})) ) {
    # OBJ->param(-name=>'..', -value=>'...') syntax:
    return $self->set_param($args->{'-name'}, $args->{'-value'}||$args->{'-values'});

  }
  if ( defined($args->{'-name'}) ) {
    # OBJ->param(-name=>'...') syntax:
    return $self->get_param($args->{'-name'});
     
  }
  if ( defined($args->{'-block'}) && (defined($args->{'-values'}) || defined($args->{'-value'})) ) {
    return $self->set_block($args->{'-block'}, $args->{'-values'}||$args->{'-value'});
  }
  if ( defined($args->{'-block'}) ) {
    return $self->get_block($args->{'-block'});
  }
    
  if ( @_ % 2 ) {
    croak "param(): illegal syntax";
  }
  my $nset = 0;
  for ( my $i = 0; $i < @_; $i += 2 ) {
    $self->set_param($_[$i], $_[$i+1]) && $nset++;
  }
  return $nset;
}




sub get_param {
  my ($self, $arg) = @_;

  unless ( $arg ) {
    croak "Usage: OBJ->get_param(\$key)";
  }
  $arg = lcase($arg);
  my $syntax = $self->{_SYNTAX} or die "'_SYNTAX' is undefined";
  # If it was an ini-style, we should first
  # split the argument into its block name and key
  # components:
  my $rv = undef;
  if ( $syntax eq 'ini' ) {
    my ($block_name, $key) = $arg =~ m/^([^\.]+)\.(.*)$/;
    if ( defined($block_name) && defined($key) ) {
      $rv = $self->{_DATA}->{$block_name}->{$key};
    } else {
      $rv = $self->{_DATA}->{$DEFAULTNS}->{$arg};
    }
  } else {
    $rv = $self->{_DATA}->{$arg};
  }

  defined($rv) or return;

  for ( my $i=0; $i < @$rv; $i++ ) {
    $rv->[$i] =~ s/\\n/\n/g;
  }  
  return @$rv==1 ? $rv->[0] : (wantarray ? @$rv : $rv);
}




sub get_block {
  my ($self, $block_name)  = @_;

  unless ( $self->syntax() eq 'ini' ) {
    croak "get_block() is supported only in 'ini' files";
  }
  unless ( defined $block_name ) {
    return keys %{$self->{_DATA}};
  }
  my $rv = {};
  while ( my ($k, $v) = each %{$self->{_DATA}->{$block_name}} ) {
    $v =~ s/\\n/\n/g;
    $rv->{$k} = $v->[1] ? $v : $v->[0];
  }
  return $rv;
}





sub set_block {
  my ($self, $block_name, $values) = @_;

  unless ( $self->syntax() eq 'ini' ) {
    croak "set_block() is supported only in 'ini' files";
  }
  my $processed_values = {};
  while ( my ($k, $v) = each %$values ) {
    $v =~ s/\n/\\n/g;
    $processed_values->{$k} = (ref($v) eq 'ARRAY') ? $v : [$v];
    $self->_is_modified(1);
  }

  $self->{_DATA}->{$block_name} = $processed_values;
  $self->_is_modified(1);
}





sub set_param {
  my ($self, $key, $value) = @_;

  my $syntax = $self->{_SYNTAX} or die "'_SYNTAX' is not defined";  
  if ( ref($value) eq 'ARRAY' ) {
    for (my $i=0; $i < @$value; $i++ ) {
      $value->[$i] =~ s/\n/\\n/g;
    }
  } else {
    $value =~ s/\n/\\n/g;
  }
  unless ( ref($value) eq 'ARRAY' ) {
    $value = [$value];
  }
  $key = lcase($key);
  # If it was an ini syntax, we should first split the $key
  # into its block_name and key components
  if ( $syntax eq 'ini' ) {
    my ($bn, $k) = $key =~ m/^([^\.]+)\.(.*)$/;
    if ( $bn && $k ) {
      $self->_is_modified(1);
      return $self->{_DATA}->{$bn}->{$k} = $value;
    }
    # most likely the user is assuming default name space then?
    # Let's hope!
    $self->_is_modified(1);
    return $self->{_DATA}->{$DEFAULTNS}->{$key} = $value;
  }
  $self->_is_modified(1);
  return $self->{_DATA}->{$key} = $value;
}








sub write {
  my ($self, $file) = @_;

  $file ||= $self->{_FILE_NAME} or die "Neither '_FILE_NAME' nor \$filename defined";

  my $fh;
  unless ( sysopen($fh, $file, O_WRONLY|O_CREAT, 0666) ) {
    $self->error("'$file' couldn't be opened for writing: $!");
    return undef;
  }
  unless ( flock($fh, LOCK_EX) ) {
    $self->error("'$file' couldn't be locked: $!");
    return undef;
  }
  unless ( truncate($fh, 0) ) {
      $self->error("'$file' couldn't be truncated: $!");
      return undef;
  }
  print $fh $self->as_string();
  unless ( CORE::close($fh) ) {
    $self->error("Couldn't write into '$file': $!");
    return undef;
  }
  return 1;
}



sub save {
  my $self = shift;
  return $self->write(@_);
}


# generates a writable string
sub as_string {
    my $self = shift;

    my $syntax = $self->{_SYNTAX} or die "'_SYNTAX' is not defined";
    my $sub_syntax = $self->{_SUB_SYNTAX} || '';
    my $currtime = localtime;
    my $STRING = undef;
    if ( $syntax eq 'ini' ) {
        $STRING .= "; Config::Simple $VERSION\n";
        $STRING .= "; $currtime\n\n";
        while ( my ($block_name, $key_values) = each %{$self->{_DATA}} ) {
            unless ( $sub_syntax eq 'simple-ini' ) {
                $STRING .= sprintf("[%s]\n", $block_name);
            }
            while ( my ($key, $value) = each %{$key_values} ) {
                my $values = join (WRITE_DELIM, map { quote_values($_) } @$value);
                $STRING .= sprintf("%s=%s\n", $key, $values );
            }
            $STRING .= "\n";
        }
    } elsif ( $syntax eq 'http' ) {
        $STRING .= "# Config::Simple $VERSION\n";
        $STRING .= "# $currtime\n\n";
        while ( my ($key, $value) = each %{$self->{_DATA}} ) {
            my $values = join (WRITE_DELIM, map { quote_values($_) } @$value);
            $STRING .= sprintf("%s: %s\n", $key, $values);
        }
    } elsif ( $syntax eq 'simple' ) {
        $STRING .= "# Config::Simple $VERSION\n";
        $STRING .= "# $currtime\n\n";
        while ( my ($key, $value) = each %{$self->{_DATA}} ) {
            my $values = join (WRITE_DELIM, map { quote_values($_) } @$value);
            $STRING .= sprintf("%s %s\n", $key, $values);
        }
    }
    $STRING .= "\n";
    return $STRING;
}





# quotes each value before saving into file
sub quote_values {
    my $string = shift;

    if ( ref($string) ) {   $string = $_[0] }
    $string =~ s/\\/\\\\/g;

    if ( $USEQQ && ($string =~ m/\W/) ) {
        $string =~ s/"/\\"/g;
        $string =~ s/\n/\\n/g;
        return sprintf("\"%s\"", $string);
    }
    return $string;
}



# deletes a variable
sub delete {
  my ($self, $key) = @_;

  my $syntax = $self->syntax() or die "No 'syntax' is defined";
  if ( $syntax eq 'ini' ) {
    my ($bn, $k) = $key =~ m/([^\.]+)\.(.*)/;
    if ( defined($bn) && defined($k) ) {
      delete $self->{_DATA}->{$bn}->{$k};
    } else {
      delete $self->{_DATA}->{$DEFAULTNS}->{$key};
    }
    return 1;
  }
  delete $self->{_DATA}->{$key};
}



# clears the '_DATA' entirely.
sub clear {
  my $self = shift;
  map { $self->delete($_) } $self->param;
}




1;
__END__;


# Following methods are loaded on demand.



# returns all the keys as a hash or hashref
sub vars {
  my $self = shift;

  # it might seem we should have used get_param() or param()
  # methods to make the task easier, but param() itself uses 
  # vars(), so it will result in a deep recursion
  my %vars = ();
  my $syntax = $self->{_SYNTAX} or die "'_SYNTAX' is not defined";
  if ( $syntax eq 'ini' ) {
    while ( my ($block, $values) = each %{$self->{_DATA}} ) {
      while ( my ($k, $v) = each %{$values} ) {
        $vars{"$block.$k"} = (@{$v} > 1) ? $v : $v->[0];
      }
    }
  } else {
    while ( my ($k, $v) = each %{$self->{_DATA}} ) {
      $vars{$k} = (@{$v} > 1) ? $v : $v->[0];
    }
  }
  return wantarray ? %vars : \%vars;
}





# imports names into the caller's namespace as global variables.
# I'm not sure how secure this method is. Hopefully someone will
# take a look at it for me
sub import_names {
  my ($self, $namespace) = @_;

  unless ( defined $namespace ) {    
    $namespace = (caller)[0];
  }
  if ( $namespace eq 'Config::Simple') {
    croak "You cannot import into 'Config::Simple' package";
  }
  my %vars = $self->vars();
  no strict 'refs';
  while ( my ($k, $v) = each %vars ) {
    $k =~ s/\W/_/g;
    ${$namespace . '::' . uc($k)} = $v;
  }
}



# imports names from a file. Compare with import_names.
sub import_from {
  my ($class, $file, $arg) = @_;

  if ( ref($class) ) {
    croak "import_from() is not an object method.";
  }
  # this is a hash support
  if ( defined($arg) && (ref($arg) eq 'HASH') ) {
    my $cfg = $class->new($file) or return;
    map { $arg->{$_} = $cfg->param($_) } $cfg->param();
    return $cfg;
  }
  # following is the original version of our import_from():
  unless ( defined $arg ) {
    $arg = (caller)[0];
  }  
  my $cfg = $class->new($file) or return;
  $cfg->import_names($arg);
  return $cfg;
}




sub error {
  my ($self, $msg) = @_;

  if ( $msg ) {
    $errstr = $msg;
  }
  return $errstr;
}





sub dump {
  my ($self, $file, $indent) = @_;

  require Data::Dumper;
  my $d = new Data::Dumper([$self], [ref $self]);
  $d->Indent($indent||2);
  if ( defined $file ) {
    my $fh;
    sysopen($fh, $file, O_WRONLY|O_CREAT|O_TRUNC, 0666) or die $!;
    print $fh $d->Dump();
    CORE::close($fh) or die $!;
  }
  return $d->Dump();
}


sub verbose {
  DEBUG or return;
  carp "****[$0]: " .  join ("", @_);
}




#------------------
# tie() interface
#------------------

sub TIEHASH {
  my ($class, $file, $args) = @_;

  unless ( defined $file ) {
    croak "Usage: tie \%config, 'Config::Simple', \$filename";
  }  
  return $class->new($file);
}


sub FETCH {
  my $self = shift;

  return $self->param(@_);
}


sub STORE {
  my $self = shift;

  return $self->param(@_);
}



sub DELETE {
  my $self = shift;

  return $self->delete(@_);
}


sub CLEAR {
  my $self = shift;
  map { $self->delete($_) } $self->param();
}


sub EXISTS {
  my ($self, $key) = @_;

  my $vars = $self->vars();
  return exists $vars->{$key};
}



sub FIRSTKEY {
  my $self = shift;

  # we make sure that tied hash is created ONLY if the program
  # needs to use this functionality.
  unless ( defined $self->{_TIED_HASH} ) {    
    $self->{_TIED_HASH} = $self->vars();
  }
  my $temp = keys %{ $self->{_TIED_HASH} };
  return scalar each %{ $self->{_TIED_HASH} };
}


sub NEXTKEY {
  my $self = shift;

  unless ( defined $self->{_TIED_HASH} ) {
    $self->{_TIED_HASH} = $self->vars();
  }
  return scalar each %{ $self->{_TIED_HASH} };
}





# -------------------
# deprecated methods
# -------------------

sub write_string {
  my $self = shift;

  return $self->as_string(@_);
}

sub hashref {
  my $self = shift;

  return scalar( $self->vars() );
}

sub param_hash {
  my $self = shift;

  return ($self->vars);
}

sub errstr {
  my $self = shift;
  return $self->error(@_);
}


sub block {
  my $self = shift;
  return $self->get_block(@_);
}

