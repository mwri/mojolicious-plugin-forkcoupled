# Mojolicious::Plugin::ForkCoupled - Mojolicious fully bidirectional forked process

Mojolicious process fork with fully bidirectional communication; three streams
(stdin, stdout and stderr). Inherits from Mojolicious::Plugin and
Mojo::EventEmitter.

## Contents

1. [Synopsis](#synopsis).
2. [Methods](#methods).
   1. [fork_exec](#fork_exec).
   2. [write_stdin](#write_stdin).
   3. [abort](#abort).
   4. [cmd](#cmd).
   5. [ctrlr](#ctrlr).
   6. [pid](#pid).
   7. [ref](#ref).
   8. [stdin](#stdin).
   9. [stdout](#stdout).
   10. [stderr](#stderr).
3. [Author](#author).

## Synopsis

Example Mojolicious lite app implementing a fork of an interactive perl
script:

```perl
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
```

Run it, as "perl mojoliteforkexample.pl daemon" perhaps. The sleeps in
this example child '/tmp/coupledforktestchild.pl' will generate
staggered output to the client:

```perl
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
```

Here's an example of the output, using 'curl' as a client:

```sh
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
```

## Methods

### fork_exec

te a new background forked process. The parent returns a
licious::Plugin::ForkCoupled object. The child won't return, because exec
alled.

```perl
my $child1 = Mojolicious::Plugin::ForkCoupled->fork_exec(
    'cmd'     => '/path/to/executable',
    'ctrlr'   => $c,
    );
```

```perl
my $child2 = Mojolicious::Plugin::ForkCoupled->fork_exec(
    'cmd'     => ['/path/to/executable', 'arg1', 'arg2'],
    'ctrlr'   => $c,
    );
```

### write_stdin

Write to the standard input of the child.

```perl
$child->write_stdin("child_command info data stuff\n");
```

### abort

Terminate the child process.

### cmd

Return the command that is to be or has been executed. Called in a list
context the command and all arguments are returned, and in a scalar context
just the command is returned, without the arguments.

### ctrlr

Return the controller (prevailing when the Mojo::MyFork object was
established).

### pid

Return the pid of the child process.

### ref

Return the ref; user data passed to 'new'.

### stdin

Return the standard input Mojo::IOLoop::Stream object.

### stdout

Return the standard output Mojo::IOLoop::Stream object.

### stderr

Return the standard error Mojo::IOLoop::Stream object.

## Author

Copyright (C) 2015-2016 Michael Wright <mjw@methodanalysis.com>.
