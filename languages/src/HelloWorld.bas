Dim greeting As String
Dim count As Integer
Dim total As Integer
Dim i As Integer

Sub PrintBanner(msg As String)
    Print "--- " & msg & " ---"
End Sub

Function Add(a As Integer, b As Integer) As Integer
    Add = a + b
End Function

greeting = "Hello, World!"
count = 5

PrintBanner(greeting)

total = Add(10, 32)
Print "10 + 32 = " & total

If total > 40 Then
    Print "Total is greater than 40"
Else
    Print "Total is 40 or less"
End If

Print "Counting to " & count & ":"
For i = 1 To count
    Print "  Step " & i
Next i

i = 0
While i < 3
    Print "While pass: " & (i + 1)
    i = i + 1
Wend
