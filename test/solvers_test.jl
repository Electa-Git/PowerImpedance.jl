
#  Example from ECEN 615
#  Methods of Electric Power 
#  Systems Analysis
#  Lecture 17:EMSs, SVD, Pseudo Inverse, Equivalents
#  Prof. Tom Overbye
# TODO: Add testing of y_node and y_edge here :)
Y=[-0.0-20.83*im   0.0+16.67*im   0.0+4.17*im   0.0+0.0*im    0.0+0.0*im     0.0+0.0*im     0.0+0.0*im
  0.0+16.67*im  -0.0-52.78*im   0.0+5.56*im   0.0+5.56*im   0.0+8.33*im    0.0+16.67*im   0.0+0.0*im
  0.0+4.17*im    0.0+5.56*im   -0.0-43.1*im   0.0+33.3*im   0.0+0.0*im     0.0+0.0*im     0.0+0.0*im
  0.0+0.0*im     0.0+5.56*im    0.0+33.3*im  -0.0-43.1*im   0.0+4.17*im    0.0+0.0*im     0.0+0.0*im
  0.0+0.0*im     0.0+8.33*im    0.0+0.0*im    0.0+4.17*im  -0.0-29.17*im   0.0+0.0*im     0.0+16.67*im
  0.0+0.0*im     0.0+16.67*im   0.0+0.0*im    0.0+0.0*im    0.0+0.0*im    -0.0-25.0*im    0.0+8.33*im
  0.0+0.0*im     0.0+0.0*im     0.0+0.0*im    0.0+0.0*im    0.0+16.67*im   0.0+8.33*im   -0.0-25.0*im]


# Test set with validation values slightly different due to rounding errors
Y_validation=[-28.128*im  11.463*im   16.667*im    0;
	11.463*im   -28.130*im   0   16.667*im;
	 16.667*im   0   -25.0*im   8.333*im;
	0   16.667*im    8.333*im  -25*im]

@test PowerImpedanceACDC.kron(Y, [2, 5, 6, 7]) ≈ Y_validation atol=1e-1

