library("dplyr")
library("ggplot2")
library("grid")
library("reshape2")
library("scales")
library("XML")
library("xtable")
library("zoo")

# First row w/ headers breaks
polls <- readHTMLTable("http://ukpollingreport.co.uk/scottish-independence-referendum", skip.rows=1)[[1]]
colnames(polls) <- c("pollster", "date", "yes", "no",
                     "non-voting", "dontknow", "yessplit")

# inspect
str(polls)

f2n <- function(x)
  as.numeric(as.character(x))

polls$date <- as.Date(polls$date, format="%d/%m/%y")
polls$yes <- f2n(polls$yes)
polls$no <- f2n(polls$no)
polls$dontknow <- f2n(polls$dontknow)
polls.orig <- polls

polls <- melt(polls, id.vars=c("pollster", "date"), 
     measure.var=c("yes", "no", "dontknow"))
colnames(polls)[3] <- "response"
levels(polls$response) <- c("Yes", "No", "Undecided")

pdf("figures/indyref_trends.pdf", 7, 6)
ggplot(polls, aes(x=date, y=value, col=response, fill=response)) + 
  geom_point() + geom_smooth(method="loess", alpha=I(.2)) +
  theme_blm() + 
  theme(legend.position=c(.5,.1), legend.direction="horizontal") +
  scale_color_brewer(type="qual", palette=3) +
  scale_fill_brewer(type="qual", palette=3) +
  scale_x_date(labels = date_format("%b '%y")) +
  scale_y_continuous(breaks=seq(0, 70, 10), limits=c(0,70)) +
  ggtitle("Should Scotland be an independent country?") +
  labs(x="", y="%", fill="Poll response:", col="Poll response:")
dev.off()



## results per pollster
polls$pollster <- gsub(" ?\\(.*", "", polls$pollster)
polls$pollster <- gsub("-", " ", polls$pollster)

cols <- do.call(rbind, strsplit(as.character(polls$pollster), "/"))
colnames(cols) <- c("company", "newspaper")

# commision
newspapers <- c("Sunday Times", "Times", "Scotsman on Sunday",
                "Daily Mail", "Mail on Sunday", #"Sunday Express",
                "Sun", "Daily Record")#, "Sunday Post")

#company
company <- c("Panelbase", "YouGov", "Ipsos MORI", "Survation",
             "ICM", "TNS-?BMRB", "Progressive", "Ashcroft",
             "Angus Reid")

polls <- cbind(polls, cols)

## Residual analysis per pollster or commisioning entity
l.y <- loess(value ~ as.numeric(date), data=subset(polls, response=="Yes"))
l.n <- loess(value ~ as.numeric(date), data=subset(polls, response=="No"))
l.u <- loess(value ~ as.numeric(date), data=subset(polls, response=="Undecided"))
with(polls, plot(as.numeric(date), value))
lines(as.numeric(polls[polls$response == "Yes",]$date),
      predict(l.y, as.numeric(polls[polls$response == "Yes",]$date)))

# Calculate predicted values per row, 
polls$predicted <- NA
loessPred <- function(resp, model){
  rows <- polls$response == resp
  curr <- polls[rows,]
  preds <- with(curr, predict(model, as.numeric(date)))
  polls[rows,]$predicted <<- preds
}

loessPred("Yes", l.y)
loessPred("No", l.n)
loessPred("Undecided", l.u)

polls$residual <- polls$value - polls$predicted
hist(polls$residual)

## Order newspaper by median residual:
ordering <- group_by(polls, newspaper) %>%
  filter(response == "Yes") %>%
  summarise(med = median(residual, na.rm=T), count=n()) %>%
  arrange(med) 
polls$newspaper <- factor(polls$newspaper, levels=ordering$newspaper)

## Testing for biases by a given pollster or newspaper/org commisioning a poll
pdf("figures/indyref_YesBiasNewspapers.pdf", 6, 6)
ggplot(subset(polls, response == "Yes" & 
                newspaper %in% ordering[ordering$count > 1,"newspaper"]), 
       aes(x=newspaper, y=residual)) +
  geom_hline(aes(yintercept=0)) +
  geom_violin(scale="width", fill=I("grey90"), col=I("grey90")) + 
  geom_jitter(position=position_jitter(width=.05)) + 
  stat_summary(geom = "crossbar", width=0.65, fatten=2, 
               color="grey40", fun.y=median, fun.ymin=median, fun.ymax=median) +
  #stat_summary(fun.y="mean_cl_boot", geom="point", col=I("red")) +
  coord_flip() + theme_blm() + ggtitle("Relative yes responses") +
  labs(x="Poll commissioner / publisher",
       y="Comparison with other polls at the time") +
  ylim(-13,13)
dev.off()

## Stat significance:
options(scipen=0)
group_by(subset(polls, response == "Yes" & 
         newspaper %in% ordering[ordering$count > 1,"newspaper"]), newspaper) %>%
  summarise(p=wilcox.test(residual, mu=0)$p.value)


ord.2 <- group_by(polls, company) %>%
  filter(response == "Yes") %>%
  summarise(med = median(residual, na.rm=T), count=n()) %>%
  arrange(med) 
polls$company <- factor(polls$company, levels=ord.2$company)

pdf("figures/indyref_YesBiasPollsters.pdf", 6, 6)
ggplot(subset(polls[complete.cases(polls),], response == "Yes" & 
                company %in% ord.2[ord.2$count > 1,"company"]), 
       aes(x=company, y=residual)) +
  geom_hline(aes(yintercept=0)) +
  geom_violin(scale="width", fill=I("grey90"), col=I("grey90")) + 
  geom_jitter(position=position_jitter(width=.05)) + 
  stat_summary(geom = "crossbar", width=0.65, fatten=2, 
               color="grey40", fun.y=median, fun.ymin=median, fun.ymax=median) +
  coord_flip() + theme_blm() + ggtitle("Relative yes responses") +
  labs(x="Pollster",
       y="Comparison with other polls at the time") +
  ylim(-13,13)
dev.off()

group_by(subset(polls, response == "Yes" & 
                  company %in% ord.2[ord.2$count > 1,"company"]), company) %>%
  summarise(p=wilcox.test(residual, mu=0)$p.value)

## generate HTML table
xt <- data.frame(date=rep("12-15 Aug", 2),
                 pollster=c("YouGov", "Panelbase"),
                 client=c("The Times", "Yes Scotland"),
                 sample.size=c(1085, 1026),
                 yes=c(38, 42),
                 no=c(51, 46), 
                 undecided=c(11, 12),
                 spread=c(13, 4))
print(xtable(xt), type="html")

polls.orig$perc <- with(polls.orig, 100*(yes / (yes+no)))
pdf("figures/indyref_yesPercent.pdf", 7, 4)
ggplot(polls.orig, aes(x=date, y=perc, ymin=0, ymax=perc)) +
  theme_blm() + geom_ribbon(fill=I("grey90")) +
  #geom_point() + 
  geom_line() + geom_smooth(method="lm", col=I("darkgrey")) +
  labs(y="Yes support (%)", x="") + 
  geom_hline(yintercept=50, col=I("#ffa775")) +
  scale_x_date(breaks="4 months", minor_breaks=NULL, 
               labels=date_format("%b '%y"), expand=c(.05,-5)) +
  scale_y_continuous(breaks=seq(0, 100, by=10), limits=c(0,60))
dev.off()

## Sily stuff:
lmod <- lm(perc ~ date, data=polls.orig)
summary(lmod)
predict(lmod, data.frame(date=as.Date("2014-09-18")), se.fit=T)
# 42.94 % yes, +- .78*2.58
# 40.9 to 45.0