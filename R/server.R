
##' nREPL Server.
##'
##' nREPL server is a blocking connection that waits for requests from the nREPL
##' client and sends the responses back.
##'
##' \code{default_handler} returns a handler which is a stack of handlers
##' produced by default middlewares.
##'
##' @name server
##' @param port Port number on which to start an nREPL server.
##' @param handler Function of variable arity to process incoming requests.
##' @param transport_fn Constructor that returns a transport connection
##' object. See \code{\link{transport}}.
##' @seealso \link{middlewares}
##' @export
start_server <- function(port = 4005, ## as.integer(runif(1, 4000, 99999)), 
                         handler = default_handler(),
                         transport_fn = transport_bencode){
    ## fixme: implement programmatic way to end the server?
    while(TRUE){
        cat("nREPL server started on port", port, "\nWaiting for connection ... ")
        ss <- socketConnection(port = port, server = TRUE,
                               open = "r+b", blocking = TRUE)
        transport <- transport_fn(ss)
        on.exit(transport$close())
        cat("connected.\n")
        tryCatch(handle_messages(transport, handler),
                 endOfInput = function(c){
                     cat(c$message)
                     ## R doesn't allow re-connection, so close and restart
                     transport$close()
                 })
    }
}

##' @rdname server
##' @param additional_middlewares A list of middleware functions to merge into
##' the list of default \code{\link{middlewares}}
##' @export
default_handler <- function(additional_middlewares = list()){
    mws <- c(as.list(middlewares), additional_middlewares)
    mws <- linearize_mws(mws)
    pre_handle(Reduce(function(f, h){ force(h); f(h)},
                      mws, init = unknown_op, right = T))
}

## default_handler <- function(additional_middlewares = list()){
##     pre_handle(mw_session(mw_eval(mw_describe(unknown_op))))
## }


handle_messages <- function(tr, handler){
    while(TRUE){

        ## read message (re-init every 10 sec)
        tryCatch(msg <- tr$read(10),
                 error = function(e) {
                     ## this is how we detect when connection was closed by peer
                     cond <- simpleCondition("End of input. Client closed?\n")
                     class(cond) <- c("endOfInput", class(cond))
                     signalCondition(cond)
                 })


        ## handle
        if(!is.null(msg)){
            tryCatch(do.call(handler, assoc(msg, tr = tr)),
                     error = function(e){
                         cat("Unhandled exception on message\n")
                         print(msg)
                         cat(as.character(e))
                         tr$write(errorfor(msg, e$message,
                                           additional_status = list("unhandled-exception")))
                     },
                     backToTopError = function(c){
                         tr$write(errorfor(msg, c$message, additional_status = c$status))
                     }, 
                     backToTop = function(c) NULL)
        }
    }
}
