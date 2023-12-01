import serial
import time
import pyqtgraph as pg
from pyqtgraph.Qt import QtGui, QtCore
import matplotlib.pyplot as plt
import numpy as np
from scipy import signal

ser = serial.Serial('/dev/tty.usbserial-00001014B', 800000, timeout=None, xonxoff=False, rtscts=False, dsrdtr=False)

ser.flushInput()
ser.flushOutput()

numlags = 30
counter = 0
meta_counter = 0
curstr = bytearray(8 * numlags)
synced = False

r_index = 0

num1 = 0
num2 = 0

s1 = []
s2 = []

counter = 0
maxcounter = 100

byteoffset = 0
fixed = 0

win = signal.windows.blackmanharris(128)

c = 0.

#plt.figure()

while (counter < maxcounter):
  counter = counter + 1
  ser.flush()
  data_raw = ser.read(2048 - byteoffset)
  print(time.time_ns() / 1000000000.)
  data_raw = np.array([i for i in data_raw])
  ii = np.where(data_raw == 255)[0]
  print(len(data_raw), ii)
  # If we see two consecutive bytes with value FF, we have our marker.
  diffarray = np.array(list(ii) + [-1000]) - np.array([-1000] + list(ii))
  idx = np.where(diffarray == 1)[0]
  print(idx)
  if (byteoffset != 0):
    byteoffset = 0
  if (len(idx) > 0):
    # We have a reference sample!
    print("FF FF found!")
    if (fixed == 0):
      byteoffset = ii[idx[0] - 1]
      #fixed = 1
    print(byteoffset)
  else:
    if (len(data_raw) == 512):
      orderedsamples = np.reshape(data_raw, (int(len(data_raw)/4), 2, 2))
      c = np.copy(orderedsamples)
      s1 = orderedsamples[:,0,0] + orderedsamples[:,0,1] * 256
      s2 = orderedsamples[:,1,0] + orderedsamples[:,1,1] * 256
      s1 = s1 - np.mean(s1)
      s2 = -(s2 - np.mean(s2))
      ff1 = np.fft.rfft(s1 * win)
      ff2 = np.fft.rfft(s2 * win)
      corr = ff1 * np.conj(ff2)
      lag = np.fft.fftshift(np.fft.irfft(corr))
      #plt.plot(lag)

  """
  if (r_index == 0):
    num1 = int.from_bytes(data_raw, byteorder='big')
    r_index = r_index + 1
  elif (r_index == 1):
    num1 = num1 + 256 * int.from_bytes(data_raw, byteorder='big')
    r_index = r_index + 1
  elif (r_index == 2):
    num2 = int.from_bytes(data_raw, byteorder='big')
    r_index = r_index + 1
  elif (r_index == 3):
    num2 = num2 + 256 * int.from_bytes(data_raw, byteorder='big')
    r_index = 0
    s1.append(num1)
    s2.append(num2)
    counter = counter + 1
  """

  """
  if (data_raw == b'\xcc' and not synced):
    counter = 0
    synced = True
  curstr[8 * numlags - 1 - counter] = int.from_bytes(data_raw, byteorder='big')
  counter = counter + 1
  if (counter == 8 * numlags):
    #global curve, ptr, nums
    nums = []
    for i in range(0, numlags):
      #print(curstr[i * 8: (i+1) * 8])
      nums.append(int.from_bytes(curstr[8*i:8*(i+1)], byteorder='big', signed=True))
    #print(numstr)
    nums = (np.array(nums) - np.mean(nums)) * 50.
    if (np.max(nums) > 8e5):
      nums = 8e5 * nums / np.max(nums)
    counter = 0
    curstr[8 * numlags - 1 - counter] = int.from_bytes(data_raw, byteorder='big')
    curve.setData(nums)
    curve.setPos(0,0)
    QtGui.QApplication.processEvents() 
  """

# TODO:
# - Find a way to clearly mark samples, using some predefined value or offset.
#   One option is to replace one in every X samples by some signal value, for both mics.
#   These samples will then be recognised and igmored by the correlator.
# - To speed up the read function, I can read the incoming bytes in blocks of, say, 1024.
#   This means I will have 256 samples for each mic (2 bytes per sample).

#plt.figure()
#plt.plot(np.array(s1))
#plt.plot(np.array(s2))

#plt.show()
