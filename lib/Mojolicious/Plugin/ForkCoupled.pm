package Mojolicious::Plugin::ForkCoupled;

use base 'Mojolicious::Plugin', 'Mojo::EventEmitter';


=head1 NAME

Mojolicious::Plugin::ForkCoupled - Mojolicious fully bidirectional forked process

=head1 DESCRIPTION

Mojolicious process fork with fully bidirectional communication; three streams
(stdin, stdout and stderr). Inherits from L<Mojolicious::Plugin> and
L<Mojo::EventEmitter>.

=head1 SYNOPSIS

Example Mojolicious lite app implementing a fork of an interactive perl script:

    #!/usr/bin/perl
    
    use Mojolicious::Lite;
    use Mojolicious::Plugin::ForkCoupled;
    
    app->plugin('Mojolicious::Plugin::ForkCoupled');
    
    get '/forktest' => sub {
    	my $c = shift;
    	my $child = app->fork_coupled(
    		'cmd' => ['/tmp/coupledforktestchild.pl', 'arg1', 'arg2'],
    		);
    	$c->write;
    	$child->on('read_stdout' => sub {
    		my $child  = shift;
    		my $stream = shift;
    		my $data   = shift;
    		foreach my $line (split /^/, $data) {
    			$c->write($line) if $c->tx;
    			$child->write_stdin(time."\n") if $line =~ /^feed me/;
    		}
    	});
    	$child->on('finish_stdout' => sub {
    		$c->finish;
    		undef $child;
    	});
    };
    
    app->start;

Run it, as "perl mojoliteforkexample.pl daemon" perhaps:

The sleeps in this example child '/tmp/coupledforktestchild.pl' will
generate staggered output to the client:

    #!/usr/bin/perl
    
    $| = 1;
    print "first $ARGV[0]\n";
    sleep 2;
    print "second $ARGV[1]\n";
    sleep 1;
    print "feed me please\n";
    my $input1 = <STDIN>;
    chomp $input1;
    sleep 2;
    print "third $input1\n";
    print "feed me again\n";
    my $input2 = <STDIN>;
    chomp $input2;
    sleep 1;
    print "final $input1 $input2\n";
    sleep 1;
    print "byebye\n";

Here's an example of the output, using 'curl' as a client:

    $ curl -i http://localhost:3000/forktest
    HTTP/1.1 200 OK
    Connection: close
    Server: Mojolicious (Perl)
    Date: Fri, 02 Dec 2016 19:15:08 GMT
    
    first arg1
    second arg2
    feed me please
    third 1480706835
    feed me again
    final 1480706835 1480706837
    byebye

=head1 METHODS

=cut


use strict;
use warnings;


our $VERSION = '1.0.0';


use Mojo::IOLoop;
use Mojo::IOLoop::Stream;


sub register {

	my $self     = shift;
	my $app      = shift;
	my $defaults = shift;

	$app->helper('fork_coupled' => sub {
		my $ctrlr = shift;
		my %args  = @_;
		$self->fork_exec(
			%$defaults,
			%args,
			'ctrlr' => $ctrlr,
			);
	});

}


sub new {

	my $class = shift;
	my %args  = @_;

	return bless {}, $class;

}


=head2 fork_exec

Create a new background forked process. The parent returns a Mojolicious::Plugin::ForkCoupled
object. The child won't return, because exec is called.

    my $child1 = Mojolicious::Plugin::ForkCoupled->fork_exec(
        'cmd'     => '/path/to/executable',
        'ctrlr'   => $c,
        );
    
    my $child2 = Mojolicious::Plugin::ForkCoupled->fork_exec(
        'cmd'     => ['/path/to/executable', 'arg1', 'arg2'],
        'ctrlr'   => $c,
        );

=cut


sub fork_exec {

	my $plugin = shift;
	my %args   = @_;

	my $class = ref $plugin;

	my $self = bless {
		'_ctrlr'        => $args{'ctrlr'},
		'_cmd'          => $args{'cmd'},
		'_timeout'      => $args{'timeout'},
		'_quash_stderr' => $args{'quash_stderr'},
		'_merge_stderr' => $args{'merge_stderr'},
		'_pre_exec_cb'  => $args{'pre_exec_cb'},
		'_ref'          => $args{'ref'},
		}, $class;

	die 'no cmd' if !defined $self->{'_cmd'};
	$self->{'_cmd'} = [ $self->{'_cmd'} ] if ref $self->{'_cmd'} eq '';
	die 'cmd must be scalar or array ref' if ref $self->{'_cmd'} ne 'ARRAY';

	$self->{'_pre_exec_cb'} = [] if !defined $self->{'_pre_exec_cb'};
	$self->{'_pre_exec_cb'} = [ $self->{'_pre_exec_cb'} ] if ref $self->{'_pre_exec_cb'} eq 'CODE';
	die 'pre_exec_cb must be a code ref or array ref' if ref $self->{'_pre_exec_cb'} ne 'ARRAY';

	die 'quash_stderr and merge_stderr are mutually exclusive'
		if $self->quash_stderr && $self->merge_stderr;

	my ($stdin_from, $stdin_to);
	my ($stdout_from, $stdout_to);
	my ($stderr_from, $stderr_to);

	pipe($stdin_from, $stdin_to)   or die 'could not create stdin pipe pair: '.$!;
	pipe($stdout_from, $stdout_to) or die 'could not create stdout pipe pair: '.$!;
	pipe($stderr_from, $stderr_to) or die 'could not create stderr pipe pair: '.$!;

	my $pid = fork();

	if (!defined $pid) {
		die 'fork failed: '.$!;
	} elsif ($pid) {
		close $stdin_from;
		close $stdout_to;
		close $stderr_to;
		$stdin_to = $self->_mk_stream('fh' => $stdin_to);
		$stdout_from = $self->_mk_stream('fh' => $stdout_from, 'name' => 'stdout');
		$stderr_from = $self->_mk_stream('fh' => $stderr_from, 'name' => 'stderr')
			if !$self->quash_stderr && !$self->merge_stderr;
		$stderr_from = $self->_mk_stream('fh' => $stderr_from, 'name' => 'stdout')
			if $self->merge_stderr;
	} else {
		close $stdin_to;
		close $stdout_from;
		close $stderr_from;
		open(STDIN, '>&', $stdin_from) or die 'dup stdin failed: '.$!;
		open(STDOUT, '>&', $stdout_to) or die 'dup stdout failed: '.$!;
		open(STDERR, '>&', $stderr_to) or die 'dup stderr failed: '.$!;
		foreach my $cb (@{$self->{'_pre_exec_cb'}}) {
			eval { $self->$cb() };
			die $cb, ': ', $@, "\n" if $@;
		}
		exec($self->cmd);
	}

	$self->{'_pid'}    = $pid;
	$self->{'_stdin'}  = $stdin_to;
	$self->{'_stdout'} = $stdout_from;
	$self->{'_stderr'} = $stderr_from;

	return $self;

}


=head2 write_stdin

Write to the standard input of the child.

    $child->write_stdin("child_command info data stuff\n");

=cut


sub write_stdin {

	my $self = shift;
	my $data = shift;

	$self->emit('write_stdin', $data);
	$self->stdin->write($data);

}


=head2 abort

Terminate the child process.

=cut


sub abort {

	my $self = shift;

	kill('TERM', $self->pid);
	waitpid($self->pid, 0);

}


sub _mk_stream {

	my $self = shift;
	my %args = @_;

	my $stream = Mojo::IOLoop::Stream->new($args{'fh'});
	$stream->timeout($args{'timeout'} || $self->timeout) if $args{'timeout'} || $self->timeout;

	if (defined $args{'name'}) {
		my $read_ev_name  = 'read_'.$args{'name'};
		my $finish_ev_name  = 'finish_'.$args{'name'};
		$stream->on('read' => sub { $self->emit($read_ev_name, @_) });
		my $stream_id = Mojo::IOLoop->singleton->stream($stream);
		$stream->on($_ => sub {
			Mojo::IOLoop->singleton->remove($stream_id);
			$self->emit($finish_ev_name, $_, @_);
			}) foreach qw/error timeout close/;
	} else {
		my $stream_id = Mojo::IOLoop->singleton->stream($stream);
		$stream->on($_ => sub {
			Mojo::IOLoop->singleton->remove($stream_id);
			}) foreach qw/error timeout close/;
	}

	return $stream;

}


=head2 cmd

Return the command that is to be or has been executed. Called in a
list context the command and all arguments are returned, and in a
scalar context just the command is returned, without the arguments.

=head2 ctrlr

Return the controller (prevailing when the Mojo::MyFork object was
established).

=head2 pid

Return the pid of the child process.

=head2 ref

Return the ref; user data passed to L<'new'>.

=head2 stdin

Return the standard input L<Mojo::IOLoop::Stream> object.

=head2 stdout

Return the standard output L<Mojo::IOLoop::Stream> object.

=head2 stderr

Return the standard error L<Mojo::IOLoop::Stream> object.

=cut

sub cmd          { wantarray ? @{$_[0]->{'_cmd'}} : $_[0]->{'_cmd'}->[0] }
sub ref          { $_[0]->{'_ref'}                                       }
sub ctrlr        { $_[0]->{'_ctrlr'}                                     }
sub pid          { $_[0]->{'_pid'}                                       }
sub stdin        { $_[0]->{'_stdin'}                                     }
sub stdout       { $_[0]->{'_stdout'}                                    }
sub stderr       { $_[0]->{'_stderr'}                                    }
sub timeout      { $_[0]->{'_timeout'}                                   }
sub quash_stderr { $_[0]->{'_quash_stderr'}                              }
sub merge_stderr { $_[0]->{'_merge_stderr'}                              }


=head1 AUTHOR

Copyright (C) 2015-2016 Michael Wright <mjw@methodanalysis.com>. All rights reserved.

=cut


1;
