# Code for Mobile & Web Messaging Book

The [Mobile & Web Messaging][mwm] book is composed of examples to use either [STOMP][stomp] or [MQTT][mqtt] messaging protocols.

All the code presented in the book are available in this Git project.

    code
    ├── mqtt                      # MQTT examples
    │   ├── ios
    │   │   └── Motions           # iOS application
    │   └── web
    │       ├── motions.html      # Web application
    └── stomp                     # STOMP examples
        ├── ios
        │   └── Locations         # iOS application
        └── web
            └── locations.html    # Web application

## iOS Examples

Both iOS examples uses [CocoaPods][cocoapods] to manage their dependencies.

## STOMP Examples

The STOMP examples are covered in Chapters 2 and 3 of the book.

The Web example uses the [stomp.js][stompjs] JavaScript client libary.  
The iOS example using the [StompKit][stompkit] library.  

Both examples uses a local [ActiveMQ broker][activemq] to exchange messages.

## MQTT Examples

The MQTT examples are covered in Chapters 6 and 7 of the book.

The Web example uses the JavaScript client libary from [Eclipse Paho][paho].  
The iOS example using the [MQTTKit][mqtt] library.

Both examples uses the eclipse [MQTT sandbox server][iot.eclipse.org] to exchange messages.

&copy;2014 [Mobile & Web Messaging][mwm]

[mwm]: http://mobile-web-messaging.net
[mqtt]: http://mqtt.org
[mqttkit]: https://github.com/jmesnil/MQTTKit
[paho]: http://www.eclipse.org/paho/
[stomp]: http://stomp.github.io
[stompkit]: https://github.com/mobile-web-messaging/StompKit/
[stompjs]: http://jmesnil.net/stomp-websocket/doc/
[iot.eclipse.org]: http://iot.eclipse.org/sandbox.html
[activemq]: http://activemq.apache.org
[cocoapods]: http://cocoapods.org
