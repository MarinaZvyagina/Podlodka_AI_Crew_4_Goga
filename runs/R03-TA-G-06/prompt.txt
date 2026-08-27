Our HTTP exception classes cover most of the common client and server error codes people need
day to day — bad request, unauthorized, forbidden, not found, conflict, and so on — each as a
small, dedicated class that a developer can just throw from anywhere in their application code,
with the framework automatically turning it into the right HTTP response (correct status code,
sensible default JSON body) without any extra setup.

One status code that's conspicuously missing from that set is 429 ("too many requests" / rate
limiting). Right now, anyone who wants to signal this condition has to fall back to constructing
the generic base exception by hand and passing the numeric status code themselves, which is more
verbose and easy to get subtly wrong (inconsistent default message, wrong casing, forgetting the
status code entirely) compared to just throwing a purpose-built exception the way they would for
every other common error.

Please add the missing exception type for this status code, matching the behavior, constructor
options, and documentation style of the existing ones as closely as possible:

- a sensible default message that makes sense out of the box, with no arguments;
- the ability to override the message, or replace the entire JSON response body;
- support for the same "short description or options object with an underlying cause" pattern
  the existing exception classes already support;
- correct HTTP status code on the resulting response when the exception is thrown, uncaught,
  from a route handler.

Make sure it's importable and usable directly from application code the same way the existing
built-in ones are, and add test coverage consistent with what already exists for its siblings.
