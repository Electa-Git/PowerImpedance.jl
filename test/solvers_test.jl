
#  Example from ECEN 615
#  Methods of Electric Power 
#  Systems Analysis
#  Lecture 17:EMSs, SVD, Pseudo Inverse, Equivalents
#  Prof. Tom Overbye

Y=[-0.0-20.83*i   0.0+16.67*i   0.0+4.17*i   0.0+0.0*i    0.0+0.0*i     0.0+0.0*i     0.0+0.0*i
  0.0+16.67*i  -0.0-52.78*i   0.0+5.56*i   0.0+5.56*i   0.0+8.33*i    0.0+16.67*i   0.0+0.0*i
  0.0+4.17*i    0.0+5.56*i   -0.0-43.1*i   0.0+33.3*i   0.0+0.0*i     0.0+0.0*i     0.0+0.0*i
  0.0+0.0*i     0.0+5.56*i    0.0+33.3*i  -0.0-43.1*i   0.0+4.17*i    0.0+0.0*i     0.0+0.0*i
  0.0+0.0*i     0.0+8.33*i    0.0+0.0*i    0.0+4.17*i  -0.0-29.17*i   0.0+0.0*i     0.0+16.67*i
  0.0+0.0*i     0.0+16.67*i   0.0+0.0*i    0.0+0.0*i    0.0+0.0*i    -0.0-25.0*i    0.0+8.33*i
  0.0+0.0*i     0.0+0.0*i     0.0+0.0*i    0.0+0.0*i    0.0+16.67*i   0.0+8.33*i   -0.0-25.0*i]


# Test set with validation values slightly different due to rounding errors
Y_validation=[ -28.128*im  11.463*im   16.667*im    0;
               11.463*im   -28.130*im   0   16.667*im;
                16.667*im   0   -25.0*im   8.333*im;
               0   16.667*im    8.333*im  -25*im]

@test PowerImpedanceACDC.kron(Y,  [2,5,6,7]) ≈ Y_validation atol=1e-1

