SMTP Bounce Classifier
======================

Parse and classify SMTP bounce messages and provider FBLs (feedback loops) from *any* mail exchanger (MX)

The .procmailrc file:
---------------------
The .procmailrc file goes in the homedir of the user that recieves your bounce messages (example: /var/spool/mail/bounce/.procmailrc). This file must be named '.procmailrc'. The basic logic of the .procmailrc file is simple. Using basic regex, you define a particular SMTP header that you want to trigger the pipe to the bounce parser/classifier. In the included .procmailrc we use the 'To:' SMTP header and parse/classify any bounce message that matches

    To:<any amount of whitespace><'abuse' or 'bounce'><anything>.mydomain.com

 If you send email messages using a static MAIL FROM address, then you can definitely set this to something more literal or with less variance in the regex. 

Procmailrc filters are referenced in the order that they are listed. For the included .procmailrc any smtp message that does not match the 'To:' regex pattern goes to the next rule (deliver the message to /dev/null).

smtp-bounce-classifer.rb:
-------------------------
This expects that you send out all email messages with a custom header in the form of

    X-rcpt: <original recipient@domain.com>

Many external providers try *super* hard to redact all original recipient address info from email messages before sending it back to the sending domain (you!). Most are quite successful at doing this, so you may want to mess around with a more clever header approach, like encoding a header with some algorithm that allows the recipient address to stay hidden in the headers until you recieve it back and can "look" for it, then decode it.

The parser forcefully re-encodes all recieved messages to UTF-8. This prevents weird artifacts on messed up and foreign encodings before the message is bounced/sent back to you. It also allows for the ancient "quoted-printable" MIME encoding (an ASCII encoding that restricts line lengths to 76 characters by adding an '=' and continuing on the next line). Quoted-printable is not base64 and is extremely annoying when trying to parse text.

The classifier:
---------------
This is a bunch of regex that i fine tuned over the course of many millions of SMTP responses from many millions of external email providers. It's pretty solid, not prone to false positives and requires very infrequent adjustments. It allows for the following SMTP response classifications

    classification = "autoreply"    # all vacation and auto-responders
    classification = "blocked"      # spam, rbls, bad stuff!
    classification = "expired"      # expired deferred messages (deferred as long as your MTA's message expiry time)
    classification = "connref"      # connection refused (a tcp connection refusal!)
    classification = "deadrcpt"     # invalid, disabled, etc.. (recipient address is dead)
    classification = "delaydsn"     # message delivery was delayed
    classification = "fbl"          # established provider feedback loops (yahoo, hotmail, aol, comcast, gmail**, etc..)
    classification = "fullbox"      # could not deliver due to full inbox
    classification = "msgsize"      # message exceeds size limit for a single message
    classification = "tmperr"       # temporary error (transient error)
    classification = "unclassified" # everything else

NOTE: gmail FBLs are done with an additional header that you must be adding to messages bound for gmail.com recipients (see http://blog.returnpath.com/blog/joanna-roberts/3-steps-to-qualify-for-gmails-feedback-loop)

Once a message has been parsed and classified, the following info will be appended to a flat file in a single line in the following format

    <yyyy-MM-dd hh:mm:ss> <original recipient@domain.com> <domain.com> <classification>

This file can be tailed by something like logstash and shipped/stored somewhere via any number of different ways (see https://github.com/logstash/logstash/tree/master/lib/logstash/outputs).

For 'deadrcpt' and 'fbl' classifications, the entire recieved email message will also be logged simultaneously to a completely separate flat file. This is helpful if you have a false positive and you need to go back and inspect the recieved bounce/fbl in order to determine where the classifier failed (and hopefully modify the classifier regex so it doesn't happen again!).

