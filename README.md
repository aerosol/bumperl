bumperl
=======

Semantic version bumper for Erlang/OTP apps

Installation & usage
====================

```
$ make
$ bumperl
Argument 'app_file' is required.
Usage: bumperl [-a <app_file>] [-l <label>] [-c [<commit>]] [-t [<tag>]]

  -a, --app     .app or .app.src file
  -l, --label   major | minor | patch
  -c, --commit  Automatic git commit [default: false]
  -t, --tag     Automatic git tag (implies commit) [default: false]

$ bumperl -a src/bumperl.app.src -t -c -l minor
```
