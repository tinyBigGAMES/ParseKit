-- hello.ml — MyLang test program
-- Exercises: functions, var decls, assignment, if/else, while, print, return

-- Pipeline configuration (source-level, overrides Delphi compile-time defaults)
platform linux64;
buildmode exe;
optimize debug;
subsystem console;

func add(a: int, b: int) -> int
  return a + b;
end

func clamp(v: int, lo: int, hi: int) -> int
  if v < lo then
    return lo;
  end
  if v > hi then
    return hi;
  end
  return v;
end

var x: int := 10;
var y: int := 32;
var result: int := add(x, y);

print(result);

if result > 40 then
  print(1);
else
  print(0);
end

var i: int := 5;
while i > 0 do
  i := i - 1;
end

print(clamp(x, 3, 8));
print(clamp(100, 3, 8));
print(clamp(-5, 3, 8));
