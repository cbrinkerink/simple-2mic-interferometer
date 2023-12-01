from PyQt5 import QtWidgets, QtCore
from pyqtgraph import PlotWidget, plot
import pyqtgraph as pg
import sys  # We need sys so that we can pass argv to QApplication
import os
from random import randint

import serial
import time

import numpy as np
from scipy import signal

ser = serial.Serial('/dev/tty.usbserial-00001014B', 800000, timeout=None, xonxoff=False, rtscts=False, dsrdtr=False)

ser.flushInput()
ser.flushOutput()

s1 = []
s2 = []

byteoffset = 0
win = signal.windows.blackmanharris(128)

class MainWindow(QtWidgets.QMainWindow):

    def __init__(self, *args, **kwargs):
        super(MainWindow, self).__init__(*args, **kwargs)

        self.graphWidget = pg.PlotWidget()
        self.setCentralWidget(self.graphWidget)

        self.x1 = list(range(100))  # 100 time points
        self.y1 = [randint(0,100) for _ in range(100)]  # 100 data points
        self.x2 = list(range(100))  # 100 time points
        self.y2 = [randint(0,100) for _ in range(100)]  # 100 data points

        self.graphWidget.setYRange(-1.5e6, 1.5e6, padding=0)

        self.graphWidget.setBackground('w')

        pen1 = pg.mkPen(color=(255, 0, 0),width=3)
        pen2 = pg.mkPen(color=(0, 0, 255),width=3)
        self.data_line_1 =  self.graphWidget.plot(self.x1, self.y1, name="1", pen=pen1)
        self.data_line_2 =  self.graphWidget.plot(self.x2, self.y2, name="2", pen=pen2)
        self.timer = QtCore.QTimer()
        self.timer.setInterval(0)
        self.timer.timeout.connect(self.update_plot_data)
        self.timer.start()

    def plot(self, x, y, plotname, color):
        pen = pg.mkPen(color=color)
        self.graphWidget.plot(x, y, name=plotname, pen=pen, symbol='+', symbolSize=30, symbolBrush=(color))

    def update_plot_data(self):
      #print(time.time_ns() / 1000000000.)
      global byteoffset
      ser.flush()
      data_raw = ser.read(512 - byteoffset)
      data_raw = np.array([i for i in data_raw])
      #print(len(data_raw))
      ii = np.where(data_raw == 255)[0]
      # If we see two consecutive bytes with value FF, we have our marker.
      diffarray = np.array(list(ii) + [-1000]) - np.array([-1000] + list(ii))
      idx = np.where(diffarray == 1)[0]
      if (byteoffset != 0):
        byteoffset = 0
      if (len(idx) > 0):
        # We have a reference sample!
        byteoffset = ii[idx[0] - 1]
      else:
        if (len(data_raw) == 512):
          #orderedsamples = np.reshape(data_raw, (int(len(data_raw)/4), 2, 2))
          #s1 = orderedsamples[:,0,0] + orderedsamples[:,0,1] * 256
          #s2 = orderedsamples[:,1,0] + orderedsamples[:,1,1] * 256
          s11 = data_raw[0::4]
          s12 = data_raw[1::4]
          s21 = data_raw[2::4]
          s22 = data_raw[3::4]
          s1 = s11 + s12 * 256.
          s2 = s21 + s22 * 256.
          s1 = s1 - np.mean(s1)
          s2 = (s2 - np.mean(s2))
          ff1 = np.fft.rfft(s1 * win)
          ff2 = np.fft.rfft(s2 * win)
          corr = ff1 * np.conj(ff2)
          lag = np.fft.fftshift(np.fft.irfft(corr))

          self.x1 = range(0, len(lag))
          self.y1 = lag
          self.x2 = range(0, len(s2))
          self.y2 = s2

          self.data_line_1.setData(self.x1, self.y1)  # Update the data.
          self.data_line_2.setData(self.x2, self.y2)  # Update the data.
          #self.graphWidget.informViewBoundsChanged()
          #self.update()

      #self.x = self.x[1:]  # Remove the first y element.
      #self.x.append(self.x[-1] + 1)  # Add a new value 1 higher than the last.

      #self.y = self.y[1:]  # Remove the first
      #self.y.append( randint(0,100))  # Add a new random value.

      #self.data_line.setData(self.x, self.y)  # Update the data.

app = QtWidgets.QApplication(sys.argv)
w = MainWindow()
w.show()
sys.exit(app.exec_())
