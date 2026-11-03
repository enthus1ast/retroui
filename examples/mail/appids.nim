## The app registrations Retro Mail signs in with, so that adding an
## account is only "Sign in with Microsoft" or "Sign in with Google": the
## browser opens, you sign in, done.
##
## They name the app, not you: a client ID is public (every desktop mail
## program carries one), and Google says a desktop client's "secret" is not
## kept secret either. Make them once (docs/retromail.md says how) and put
## them here, or give them when building -- CI takes them from its secrets:
##
##   RETRO_MAIL_MICROSOFT_ID=... RETRO_MAIL_GOOGLE_ID=... \
##   RETRO_MAIL_GOOGLE_SECRET=... nimble mail
##
## Empty: the wizard asks for your own (as it does for "my organisation's
## own registration").
##
## Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

import std/os

const
  builtinMicrosoft = ""      ## Application (client) ID, entra.microsoft.com: any organisation
                             ## and personal Microsoft accounts, platform "Mobile and desktop"
                             ## with http://localhost, public client flows allowed
  builtinGoogle = ""         ## OAuth client ID of type "Desktop app", console.cloud.google.com
  builtinGoogleSecret = ""   ## ... and its client secret

proc pick(env, fallback: string): string {.compileTime.} =
  let e = getEnv(env)
  if e.len > 0: e else: fallback

const
  microsoftAppId* = pick("RETRO_MAIL_MICROSOFT_ID", builtinMicrosoft)
    ## Retro Mail's Microsoft registration ("" when this build has none)
  googleAppId* = pick("RETRO_MAIL_GOOGLE_ID", builtinGoogle)
    ## Retro Mail's Google client ("" when this build has none)
  googleAppSecret* = pick("RETRO_MAIL_GOOGLE_SECRET", builtinGoogleSecret)
    ## ... its secret
