[![Actions Status](https://github.com/FCO/Supervisor/actions/workflows/test.yml/badge.svg)](https://github.com/FCO/Supervisor/actions)

NAME
====

Supervisor - A easy way for cros-machine comunication

SYNOPSIS
========

run on a terminal:

```raku
use Supervisor;

sub bla {
   receive -> $data {
      say $data;

      $*from.send("$data: Ok")
   }
}

run-supervisor :9998port, :funcs{ :&bla }
```

on a different terminal:

```raku

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
```

when you ran tthe 2nd code, it will print:

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

and on the first terminal:

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

DESCRIPTION
===========

Supervisor is a first test of riting something near to erlang's RPC

AUTHOR
======

    <fernandocorrea@gmail.com>

COPYRIGHT AND LICENSE
=====================

Copyright 2022 

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

