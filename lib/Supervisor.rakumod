use JSON::RPC::Client;
use JSON::RPC::Server;

unit class Supervisor;

class Process { ... }

class Node {
  has Str  $.name                  = "main";
  has Str  $.host                  = "localhost";
  has UInt $.port where * <= 65535 = 1234;
  has      $!conn;

  my %by-name;
  my %by-port;

  method TWEAK(|) {
    %by-name{ $!name } = self;
    %by-port{ $!port } = self if $!host eq "localhost";
  }

  method COERCE-FROM(Str:D $str) {
    do if $str ~~ /[ $<name>=\w+ \s+ ]? $<host>=<[\w.]>+ [":" $<port>=\d+]? / {
      self.new: |(:name(.Str) with $<name>), |(:host(.Str) with $<host>), |(:port(.Int) with $<port>)
    } else {
      fail "String '$str' not recognised"
    }
  }

  multi method CALL-ME(Str $name) {
    fail "Not found Node with name '$name'" without %by-name{ $name };
    %by-name{ $name }
  }

  method Str { "{ $!name } { $!host }:{ $!port }" }

  method WHICH {
    ValueObjAt.new: "{ ::?CLASS.^name }|{ self.Str }"
  }

  method connect {
    $!conn = JSON::RPC::Client.new( url => "http://{ $!host }:{ $!port }" )
  }

  method spawn(|c) {
    my $process = $!conn.spawn: |c;
    Process.COERCE-FROM: $process
  }

  method send(|c) {
    start ($!conn //= $.connect).receive: |c
  }

  method run-server($actor) {
    note "Starting server on port $!port";
    JSON::RPC::Server.new( application => $actor ).run( :$!port, :!debug )
  }
}

class Process {
  has Node $.node .= new;
  has UInt $.pid = 0;

  method COERCE-FROM(Str:D $str) {
    do if $str ~~ /$<node>=[ [ \w+ \s+ ]? <[\w.]>+ [":" \d+]? \s+]? $<pid>=\d+/ {
      self.new: |(:node(Node.COERCE-FROM: .Str) with $<node>), :pid(+$<pid>)
    } else {
      fail "String '$str' not recognised"
    }
  }

  method Str { "{ $!node.Str } $!pid" }

  method send(|c) {
    $!node.send: $!pid.Int, $*SUP-PROCESS.Str, |c
  }
}

has Node        $.node handles <host port name> .= new;
has Node        @.nodes;
has Channel     %!channels;
has             $!server;
has Promise     $.running = start { $!server = $!node.run-server(self) };
has             %.spawned{ UInt };
has atomicint   $!next-pid = 1;
has             %.funcs;
has Lock::Async $!lock .= new;

method !channels { %!channels }

method BUILD(:@nodes, :$port, :%!funcs, |) {
  @!nodes = Array[Node].new: @nodes.map: { Node.COERCE-FROM: $_ } if @nodes;
  $!node .= new: :$port with $port;
}

method run-main(&block, :@nodes) {
  for @!nodes -> $node {
    $node.connect
  }
  my $PROCESS::SUP-PROCESS = Process.new: :$!node, :pid(0);
  block
}

method run-node(&block?) {
  my $PROCESS::SUP-PROCESS = Process.new: :$!node, :pid(0);
  .() with &block;
  await $*SUPERVISOR.running;
}

multi run-supervisor(&block, UInt :$port, :@nodes, :%funcs) is export {
  $PROCESS::SUPERVISOR = Supervisor.new: |(:$port with $port), |(:@nodes if @nodes), |(:%funcs if %funcs);
  $*SUPERVISOR.run-main: &block
}

multi run-supervisor(UInt :$port, :%funcs) is export {
  $PROCESS::SUPERVISOR = Supervisor.new: |(:$port with $port), |(:%funcs if %funcs);
  $*SUPERVISOR.run-node
}

method !channel-named($pid) {
  $!lock.protect: {
    %!channels{ $pid } //= Channel.new
  }
}

sub receive(&block) is export {
  my $supervisor = $*SUPERVISOR;
  my $sup-pid = $*SUP-PROCESS;
  given $supervisor!channel-named($sup-pid.pid) -> $chn {
    react whenever $chn -> [ Capture $data, Process $*from ] {
      my $*SUPERVISOR = $supervisor;
      my $*SUP-PROCESS = $sup-pid;
      CATCH {
        default {
          .note
        }
      }
      block |$data
    }
  }
}

proto spawn(|) is export {*}

multi spawn(Str $name, |c) {
  $*SUPERVISOR.spawn: $name, |c
}

multi spawn(Node $node, Str $name, |c) {
  $node.spawn: $name, |c
}

method spawn(Str $name, |c) {
  my UInt $pid = $!next-pid⚛++;
  %!spawned{ $pid } = start {
    my $*SUP-PROCESS = Process.new: :$!node, :$pid;
    CATCH {
      default {
        .note
      }
    }
    %!funcs{$name}.(|c)
  }
  Process.new(:$!node, :$pid).Str
}

method receive(UInt $pid, Str $process, |c) {
  $!lock.protect: {
    with %!channels{ $pid } {
      my $from = Process.COERCE-FROM: $process;
      .send: [ c, $from ]
    } else{
      die "Process $pid not waiting to receive messages."
    }
  }
}

=begin pod

=head1 NAME

Supervisor - A easy way for cros-machine comunication

=head1 SYNOPSIS


run on a terminal:

=begin code :lang<raku>
use Supervisor;

sub bla {
   receive -> $data {
      say $data;

      $*from.send("$data: Ok")
   }
}

run-supervisor :9998port, :funcs{ :&bla }
=end code

on a different terminal:

=begin code :lang<raku>
use Supervisor;

run-supervisor :nodes["node01 localhost:9998", ], {
   my $node = Supervisor::Node("node01");
   my @bla = spawn($node, "bla") xx 5;

   .send: "test " ~ ++$ for @bla;

   receive {
      .say;
      done if ++$ >= 5
   }
}
=end code

when you ran tthe 2nd code, it will print:

=begin code
Starting server on port 1234
[2022-05-02T19:34:06Z] Started HTTP server.
[2022-05-02T19:34:07Z] POST / HTTP/1.1
test 1: Ok
[2022-05-02T19:34:07Z] POST / HTTP/1.1
test 2: Ok
[2022-05-02T19:34:07Z] POST / HTTP/1.1
test 3: Ok
[2022-05-02T19:34:07Z] POST / HTTP/1.1
test 4: Ok
[2022-05-02T19:34:07Z] POST / HTTP/1.1
test 5: Ok
=end code

and on the first terminal:

=begin code
Starting server on port 9998
[2022-05-02T19:36:52Z] Started HTTP server.
[2022-05-02T19:36:57Z] POST / HTTP/1.1
[2022-05-02T19:36:57Z] POST / HTTP/1.1
[2022-05-02T19:36:57Z] POST / HTTP/1.1
[2022-05-02T19:36:58Z] POST / HTTP/1.1
[2022-05-02T19:36:58Z] POST / HTTP/1.1
[2022-05-02T19:36:58Z] POST / HTTP/1.1
test 1
[2022-05-02T19:36:58Z] POST / HTTP/1.1
test 2
[2022-05-02T19:36:58Z] POST / HTTP/1.1
[2022-05-02T19:36:58Z] POST / HTTP/1.1
[2022-05-02T19:36:58Z] POST / HTTP/1.1
test 3
test 4
test 5
=end code

=head1 DESCRIPTION

Supervisor is a first test of riting something near to erlang's RPC

=head1 AUTHOR

 <fernandocorrea@gmail.com>

=head1 COPYRIGHT AND LICENSE

Copyright 2022 

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

=end pod
