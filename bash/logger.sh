exec 1> >( logger -p local0.info -t "$SCRIPT: info" )
exec 2> >( logger -p local0.err  -t "$SCRIPT: error" )
