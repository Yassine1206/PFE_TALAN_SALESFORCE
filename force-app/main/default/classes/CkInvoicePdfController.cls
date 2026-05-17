public class CkInvoicePdfController {
  public Order ord { get; set; }

  public CkInvoicePdfController(ApexPages.StandardController ctrl) {
    this.ord = (Order) ctrl.getRecord();
  }
}
