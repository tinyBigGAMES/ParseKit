; HelloWorld.scm

(define greeting "Hello, World!")
(define count 5)
(define total 0)
(define i 0)

(define (print-banner msg)
  (display "--- ")
  (display msg)
  (display " ---")
  (newline))

(define (add a b)
  (+ a b))

(set! greeting "Hello, World!")
(set! count 5)

(print-banner greeting)

(set! total (add 10 32))
(display "10 + 32 = ")
(display total)
(newline)

(if (> total 40)
  (begin
    (display "Total is greater than 40")
    (newline))
  (begin
    (display "Total is 40 or less")
    (newline)))

(display "Counting to ")
(display count)
(display ":")
(newline)

(set! i 1)
(define (count-loop n)
  (if (<= i n)
    (begin
      (display "  Step ")
      (display i)
      (newline)
      (set! i (+ i 1))
      (count-loop n))))

(count-loop count)

(set! i 0)
(define (while-loop)
  (if (< i 3)
    (begin
      (display "While pass: ")
      (display (+ i 1))
      (newline)
      (set! i (+ i 1))
      (while-loop))))

(while-loop)
