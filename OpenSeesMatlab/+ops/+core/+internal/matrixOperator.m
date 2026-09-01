function operator = matrixOperator(matrix)
%MATRIXOPERATOR Return a matrix-vector function without densifying.
operator = @(vector) matrix * vector;
end
