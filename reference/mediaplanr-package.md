# mediaplanr: Typed Media Plans and Scenario Comparison

A thin backend that turns an uploaded media plan into a validated, typed
object at a configurable grain, derives scenarios from it by editing
planned spend, and collects them into a comparable set for charting and
export. Holds plan intent only: it does not fit models, forecast, or
optimize. Response modeling and optimization live in the 'mrmopt'
engine; their results are joined to this package's output by scenario
and grain.

## Author

**Maintainer**: Ben Denis Shaffer <my.blogdown@gmail.com>
